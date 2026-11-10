import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import {formatDateTime} from '../src/display-format.mjs';

const compiled=ts.transpileModule(readFileSync(new URL('../src/MarketPriceChart.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
test('the chart scrubs to recorded timestamps and prices with pointer and keyboard input',()=>{
 let cursor;const jsx=(type,props)=>({type,props}),module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?{useState:initial=>[cursor??initial,value=>{cursor=typeof value==='function'?value(cursor):value;}]}:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:{formatDateTime}});
 const history=[{created_at:'2026-11-09T00:00:00Z',probability:.4},{created_at:'2026-11-09T01:00:00Z',probability:.6025},{created_at:'2026-11-09T10:00:00Z',probability:.7}];
 const chart=()=>module.exports.default({history,range:'ALL',setRange(){}}).props.children.find(n=>n?.type==='svg');
 chart().props.onPointerMove({clientX:206,currentTarget:{getBoundingClientRect:()=>({left:100,width:720})}});
 assert.equal(chart().props['aria-valuetext'],'09/11/2026 02:00 · 60.25% · ◈ 0.6025 per Yes share');
 chart().props.onKeyDown({key:'End',preventDefault(){}});assert.match(chart().props['aria-valuetext'],/11:00 · 70%/);
 chart().props.onKeyDown({key:'ArrowLeft',preventDefault(){}});assert.match(chart().props['aria-valuetext'],/02:00 · 60.25%/);
});
