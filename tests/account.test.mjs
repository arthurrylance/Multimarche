import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';
const source=readFileSync(new URL('../supabase/functions/account/index.ts',import.meta.url),'utf8').replace(/^import[^\n]+\n/,'');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText;
function endpoint({validToken=true,passwordCorrect=true}={}){
 let handler,update,signOutScope;const user={id:'member-id',email:'member@members.multimarche.invalid'};
 const admin={auth:{getUser:async()=>({data:{user:validToken?user:null},error:validToken?null:new Error('Invalid token')}),admin:{updateUserById:async(id,attributes)=>{update={id,attributes};return{error:null};}}},from:()=>({select:()=>({eq:()=>({single:async()=>({data:{username:'member',active:true}})})})})};
 const client={auth:{signInWithPassword:async({password})=>({data:{user:passwordCorrect&&password==='correct-password'?user:null},error:passwordCorrect&&password==='correct-password'?null:new Error('Incorrect')}),signOut:async(opts)=>{signOutScope=opts.scope;}}};
 vm.runInNewContext(compiled,{Request,Response,createClient:(_url,key)=>key==='service'?admin:client,Deno:{env:{get:name=>({SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'service',SUPABASE_ANON_KEY:'anon'})[name]},serve:fn=>{handler=fn;}}});
 return {request:(body,token='valid')=>handler(new Request('https://example.test/account',{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)})),get update(){return update;},get scope(){return signOutScope;}};
}
test('account endpoint requires a verified session and ignores supplied target IDs',async()=>{
 const a=endpoint({validToken:false});assert.equal((await a.request({username:'member',nickname:''})).status,401);assert.equal(a.update,undefined);
 const b=endpoint();assert.equal((await b.request({username:'member',nickname:'Nick',userId:'another-user'})).status,200);assert.equal(b.update.id,'member-id');
});
test('username and password changes require current password and only revoke the reauthentication session',async()=>{
 const a=endpoint();assert.equal((await a.request({username:'changed',nickname:''})).status,400);assert.equal(a.update,undefined);
 const b=endpoint({passwordCorrect:false});assert.equal((await b.request({username:'changed',nickname:'',currentPassword:'wrong'})).status,403);assert.equal(b.update,undefined);
 const c=endpoint();assert.equal((await c.request({username:'changed',nickname:'Nick',currentPassword:'correct-password',newPassword:'new-long-password'})).status,200);assert.equal(c.update.attributes.email,'changed@members.multimarche.invalid');assert.equal(c.update.attributes.password,'new-long-password');assert.equal(c.scope,'local');
});
test('nickname edits need no password but enforce length and username constraints',async()=>{
 const a=endpoint();assert.equal((await a.request({username:'member',nickname:'A nickname'})).status,200);assert.equal(a.update.attributes.password,undefined);
 assert.equal((await a.request({username:'member',nickname:'x'.repeat(41)})).status,400);
 assert.equal((await a.request({username:'bad username',nickname:''})).status,400);
});
