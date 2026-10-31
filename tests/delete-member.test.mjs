import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';
const source=readFileSync(new URL('../supabase/functions/delete-member/index.ts',import.meta.url),'utf8').replace(/^import[^\n]+\n/,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText;
const target='00000000-0000-4000-8000-000000000999';
function endpoint({valid=true,allowed=true,authFailure=false,alreadyDeleted=false}={}){
 let handler;const calls=[];
 const service={auth:{getUser:async()=>({data:{user:valid?{id:'caller'}:null},error:null}),admin:{getUserById:async()=>({data:{user:{id:target,deleted_at:alreadyDeleted?'2026-10-31':undefined}},error:null}),deleteUser:async(id,soft)=>{calls.push(['auth',id,soft]);return{error:authFailure?new Error('Unavailable'):null};}}},from:()=>({update:row=>{calls.push(['status',row]);return{eq:()=>({eq:async()=>({error:null})})};}})};
 const caller={rpc:async(name,args)=>{calls.push(['rpc',name,args]);return{error:allowed?null:new Error('Admin access required')};}};
 vm.runInNewContext(compiled,{Request,Response,Date,createClient:(_url,key,options)=>{if(key==='service')return service;assert.equal(options.global.headers.Authorization,'Bearer token');return caller;},Deno:{env:{get:name=>({SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'service',SUPABASE_ANON_KEY:'anon'})[name]},serve:fn=>{handler=fn;}}});
 return {calls,request:(body={userId:target},token='token')=>handler(new Request('https://example.test/delete-member',{method:'POST',headers:token?{authorization:'Bearer '+token}:{},body:JSON.stringify(body)}))};
}
test('user deletion checks JWT and database admin authorization before touching Auth',async()=>{
 const missing=endpoint();assert.equal((await missing.request({},'')).status,401);assert.equal(missing.calls.length,0);
 const invalid=endpoint({valid:false});assert.equal((await invalid.request()).status,401);assert.equal(invalid.calls.length,0);
 const member=endpoint({allowed:false});assert.equal((await member.request()).status,403);assert.equal(member.calls.length,1);assert.equal(member.calls[0][0],'rpc');
});
test('deletion revokes membership before irreversible Auth cleanup and preserves the profile',async()=>{
 const app=endpoint();assert.equal((await app.request()).status,200);assert.deepEqual(app.calls.map(x=>x[0]),['rpc','auth','status']);assert.equal(app.calls[0][1],'admin_delete_member');assert.equal(app.calls[0][2].p_user,target);assert.equal(app.calls[1][1],target);assert.equal(app.calls[1][2],true);assert.ok(app.calls[2][1].auth_deleted_at);
});
test('Auth cleanup failures are retryable after access removal; invalid targets do nothing',async()=>{
 const app=endpoint({authFailure:true});const response=await app.request();assert.equal(response.status,502);assert.match((await response.json()).error,/access removed.*retry/i);assert.deepEqual(app.calls.map(x=>x[0]),['rpc','auth']);
 const bad=endpoint();assert.equal((await bad.request({userId:'not-an-id'})).status,400);assert.equal(bad.calls.length,0);
});
test('retry after completed Auth deletion records cleanup without deleting again',async()=>{
 const app=endpoint({alreadyDeleted:true});assert.equal((await app.request()).status,200);assert.deepEqual(app.calls.map(x=>x[0]),['rpc','status']);
});
