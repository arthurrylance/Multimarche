import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import ts from 'typescript';
import {readFileSync} from 'node:fs';
import * as formatting from '../src/display-format.mjs';
const compiled=ts.transpileModule(readFileSync(new URL('../src/DateInput.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function mount(exportName,initial={}){
 const state=[],effects=[],pending=[];let cursor=0,tree;const validity=new Map();
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],next=>{state[i]=typeof next==='function'?next(state[i]):next;}];},useRef:init=>{const i=cursor++;return state[i]??={current:init};},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i][j])){effects[i]=deps;pending.push(fn);}}};
 const jsx=(type,props)=>{if(typeof type==='function')return type(props);if(type==='input'&&props.ref)props.ref.current={setCustomValidity:message=>validity.set(props['aria-label'],message)};return{type,props:props??{}};},module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='./display-format.mjs'?formatting:{jsx,jsxs:jsx}});
 const props={value:'',label:'Deadline',...initial,onChange:value=>{props.value=value;}};
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
 const render=()=>{cursor=0;tree=module.exports[exportName](props);for(const effect of pending.splice(0))effect();};
 return{props,render,field:label=>walk(tree).find(n=>n.type==='input'&&n.props['aria-label']===label),change(label,value){walk(tree).find(n=>n.type==='input'&&n.props['aria-label']===label).props.onChange({target:{value},currentTarget:{setCustomValidity:message=>validity.set(label,message)}});},error:label=>validity.get(label)};
}
test('date entry retains incomplete drafts, inserts slashes for numeric keyboards and emits ISO dates',()=>{
 const app=mount('DateInput',{value:'2026-11-02'});app.render();assert.equal(app.field('Deadline').props.value,'02/11/2026');
 app.change('Deadline','0');app.render();assert.equal(app.field('Deadline').props.value,'0');assert.equal(app.props.value,'');
 app.change('Deadline','03012027');app.render();assert.equal(app.field('Deadline').props.value,'03/01/2027');assert.equal(app.props.value,'2027-01-03');assert.equal(app.error('Deadline'),'');
 app.change('Deadline','31022027');app.render();assert.equal(app.props.value,'');assert.match(app.error('Deadline'),/valid date/);
 app.props.value='2028-02-29';app.render();app.render();assert.equal(app.field('Deadline').props.value,'29/02/2028');assert.equal(app.error('Deadline'),'');
});
test('date input enforces the existing minimum date and allows an empty optional field',()=>{
 const app=mount('DateInput',{min:'2026-11-02'});app.render();app.change('Deadline','01/11/2026');app.render();assert.match(app.error('Deadline'),/02\/11\/2026 or later/);
 app.change('Deadline','');app.render();assert.equal(app.error('Deadline'),'');assert.equal(app.field('Deadline').props.required,false);
});
test('date and time controls preserve the backend local ISO contract and require both parts',()=>{
 const app=mount('DateTimeInput');app.render();app.change('Deadline time','09:00');app.render();assert.equal(app.props.value,'T09:00');assert.equal(app.field('Deadline date').props.required,true);
 app.change('Deadline date','02112026');app.render();assert.equal(app.props.value,'2026-11-02T09:00');assert.equal(app.field('Deadline date').props.value,'02/11/2026');
 app.change('Deadline time','10:30');app.render();assert.equal(app.props.value,'2026-11-02T10:30');assert.equal(app.field('Deadline time').props.required,true);
});
