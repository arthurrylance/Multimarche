import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';
const compiled=ts.transpileModule(readFileSync(new URL('../src/usePositionCosts.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function costs(rpc){
 const state=[],effects=[],cleanup=[],pending=[],calls=[];let cursor=0,result;
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=init;return[state[i],v=>state[i]=v];},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i][j])){effects[i]=deps;pending.push(()=>{cleanup[i]?.();cleanup[i]=fn();});}}};
 const module={exports:{}};vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:{supabase:{rpc:async(name,args)=>{calls.push({name,args});return rpc(name,args);}}}});
 const props={userId:'member',markets:[{id:'a',status:'open'},{id:'b',status:'resolved'}],positions:[{market_id:'a',side:'yes',shares:10,net_cost:4},{market_id:'a',side:'no',shares:2,net_cost:1},{market_id:'b',side:'yes',shares:5}],tick:0};
 return{props,calls,render(){cursor=0;result=module.exports.default(props.userId,props.markets,props.positions,props.tick);for(const fn of pending.splice(0))fn();return result;},get result(){return result;}};
}
test('cost loading calls the existing own-account RPC once per open market, after authentication',async()=>{
 const app=costs(async()=>({data:{yes:4,no:1}}));app.props.userId=undefined;app.render();await settle();assert.equal(app.calls.length,0);
 app.props.userId='member';app.render();await settle();app.render();assert.equal(app.calls.length,1);assert.equal(app.calls[0].name,'position_accounting');assert.equal(JSON.stringify(app.calls[0].args),'{"p_market":"a"}');assert.equal(app.result.costs.a.yes,4);
 app.props.positions=[...app.props.positions];app.render();await settle();assert.equal(app.calls.length,1);
});
test('changed holdings hide stale costs and a superseded or other-account response is discarded',async()=>{
 const replies=[],app=costs(()=>new Promise(resolve=>replies.push(resolve)));app.render();app.props.positions[0]={...app.props.positions[0],shares:20};app.render();assert.equal(Object.keys(app.result.costs).length,0);
 replies[1]({data:{yes:8,no:1}});await settle();app.render();assert.equal(app.result.costs.a.yes,8);
 replies[0]({data:{yes:4,no:1}});await settle();app.render();assert.equal(app.result.costs.a.yes,8);
 app.props.userId='another';app.render();assert.equal(Object.keys(app.result.costs).length,0);
});
test('failed purchase costs stay unknown and retry on refresh without inventing a net-cost basis',async()=>{
 let fail=true;const app=costs(async()=>fail?{error:{message:'offline'}}:{data:{yes:4,no:1}});app.render();await settle();app.render();assert.match(app.result.error,/could not be loaded/);assert.equal(app.result.costs.a,undefined);
 fail=false;app.props.tick++;app.render();await settle();app.render();assert.equal(app.result.error,'');assert.equal(app.result.costs.a.yes,4);
});
