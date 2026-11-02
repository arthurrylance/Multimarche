import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

const module={exports:{}},jsx=(type,props)=>({type,props});
vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/PredictionSelect.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports:module.exports,require:name=>name==='react/jsx-runtime'?{jsx,jsxs:jsx}:{}});
const options=[{id:'a',label:'Alpha',detail:'40%'},{id:'b',label:'Beta',detail:'60%'},{id:'c',label:'Gamma',detail:'70%'}];

test('clicking cycles predictions, wraps at the end and preserves keyboard selection',()=>{
 let value='a';const changes=[];
 const button=()=>module.exports.default({label:'Predictions',controls:'preview',options,value,onChange:id=>{value=id;changes.push(id);}}).props.children;
 assert.match(button().props['aria-label'],/Alpha/);assert.equal(button().props['aria-controls'],'preview');
 button().props.onClick();assert.equal(value,'b');button().props.onClick();assert.equal(value,'c');button().props.onClick();assert.equal(value,'a');
 let prevented=0;const key=key=>button().props.onKeyDown({key,preventDefault(){prevented++;}});
 key('ArrowLeft');assert.equal(value,'c');key('Home');assert.equal(value,'a');key('End');assert.equal(value,'c');key('ArrowRight');assert.equal(value,'a');
 assert.equal(prevented,4);assert.equal(button().props.onWheel,undefined);assert.deepEqual(changes,['b','c','a','c','a','c','a']);
});

test('a single prediction is disabled and an empty list has no control',()=>{
 let changed=false;const props={label:'Predictions',options:[options[0]],value:'a',onChange:()=>changed=true};
 const button=module.exports.default(props).props.children;assert.equal(button.props.disabled,true);button.props.onClick();assert.equal(changed,false);
 assert.equal(module.exports.default({...props,options:[]}),null);
});
