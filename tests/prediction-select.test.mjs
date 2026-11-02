import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';

const module={exports:{}};
vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/PredictionSelect.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports:module.exports,require:()=>({})});

test('scrolling predictions steps through current options, contains page scroll and cleans up its listener',()=>{
 let listener,registered,removed,value='a',prevented=0;
 const changes=[],options=[{id:'a',label:'A'},{id:'b',label:'B'},{id:'c',label:'C'}];
 const cleanup=module.exports.attachPredictionWheel({addEventListener(name,fn,settings){assert.equal(name,'wheel');listener=fn;registered=fn;assert.equal(settings.passive,false);},removeEventListener(name,fn){assert.equal(name,'wheel');removed=fn;}},()=>({options,value,onChange(id){value=id;changes.push(id);}}));
 const wheel=(deltaY,timeStamp,extra={})=>listener({deltaY,deltaX:0,deltaMode:0,timeStamp,preventDefault(){prevented++;},...extra});
 wheel(100,0);assert.equal(value,'b');wheel(100,40);assert.equal(value,'b');
 wheel(100,200);assert.equal(value,'c');wheel(100,400);assert.equal(value,'c');
 wheel(-100,600);assert.equal(value,'b');value='a';wheel(-100,800);assert.equal(value,'a');
 wheel(10,1000);wheel(10,1010);assert.equal(value,'a');wheel(10,1020);assert.equal(value,'b');
 wheel(3,1200,{deltaMode:1});assert.equal(value,'c');assert.deepEqual(changes,['b','c','b','b','c']);
 const before=prevented;wheel(-100,1400,{ctrlKey:true});wheel(-100,1600,{deltaX:200});assert.equal(prevented,before);assert.equal(value,'c');
 cleanup();assert.equal(removed,registered);
});
