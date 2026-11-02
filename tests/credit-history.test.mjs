import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';import * as display from '../src/display-format.mjs';
const compiled=ts.transpileModule(readFileSync(new URL('../src/CreditHistory.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function history(rpc){
 const state=[],effects=[],cleanups=[],pending=[],calls=[];let cursor=0,tree;
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=init;return[state[i],value=>state[i]=typeof value==='function'?value(state[i]):value];},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((value,j)=>value!==effects[i][j])){effects[i]=deps;pending.push(()=>{cleanups[i]?.();cleanups[i]=fn();});}}};
 const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./display-format.mjs'?display:{supabase:{rpc:async(name,args)=>{calls.push({name,args});return rpc();}}}});
 const props={userId:'member',tick:0},walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)],text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):text(n.props?.children);
 return{props,calls,render(){cursor=0;tree=module.exports.default(props);for(const fn of pending.splice(0))fn();},text:()=>text(tree),nodes:()=>walk(tree),retry:()=>walk(tree).find(n=>n.type==='button')?.props.onClick()};
}
const entries=[{id:'game:plinko:2026-11-02',game:'plinko',day:'2026-11-02',reason:'Plinko daily summary',amount:-.6,spent:2,received:1.4,transactions:4},{id:'game:snake:2026-11-02',game:'snake',day:'2026-11-02',amount:10,spent:0,received:10,transactions:10},{id:'trade',game:null,reason:'Prediction purchase',amount:-25,created_at:'2026-11-02T10:00:00Z'}];
test('history shows one daily game summary with net credits while market transactions remain individual',async()=>{
 const app=history(async()=>({data:entries}));app.render();await settle();app.render();assert.equal(app.calls[0].name,'portfolio_history');assert.equal(JSON.stringify(app.calls[0].args),'{"p_limit":100}');assert.match(app.text(),/Plinko · 02\/11\/2026/);assert.match(app.text(),/spent ◈ 2 · returned ◈ 1.4/);assert.match(app.text(),/−◈ 0.6/);assert.match(app.text(),/Snake · 02\/11\/2026/);assert.match(app.text(),/Earned ◈ 10/);assert.match(app.text(),/Prediction purchase/);assert.equal(app.nodes().filter(n=>n.type==='b').length,3);
});
test('history retries errors and discards a superseded account response',async()=>{
 let fail=true;const app=history(async()=>fail?{error:{message:'Offline'}}:{data:entries});app.render();await settle();app.render();assert.match(app.text(),/Offline/);fail=false;app.retry();app.render();await settle();app.render();assert.doesNotMatch(app.text(),/Offline/);assert.match(app.text(),/Prediction purchase/);
 const responses=[],other=history(()=>new Promise(resolve=>responses.push(resolve)));other.render();other.props.userId='new-member';other.render();responses[1]({data:[{...entries[2],reason:'New account entry'}]});await settle();other.render();responses[0]({data:entries});await settle();other.render();assert.match(other.text(),/New account entry/);assert.doesNotMatch(other.text(),/Plinko|Prediction purchase/);
});
