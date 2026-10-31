import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';
import {marketNotifications} from '../src/interactions.mjs';
const source=readFileSync(new URL('../src/NotificationsPanel.tsx',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function panel(rows=new Map(),fail=false){
 const state=[],effects=[],pending=[];let cursor=0,tree;const calls=[];
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],value=>{state[i]=typeof value==='function'?value(state[i]):value;}];},useRef:init=>{const i=cursor++;return state[i]??=( {current:init});},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i].deps[j])){effects[i]?.cleanup?.();effects[i]={deps};pending.push(()=>{effects[i].cleanup=fn();});}}};
 const supabase={from:()=>({select:()=>({eq:()=>Promise.resolve({data:[...rows].map(([event_key,dismissed])=>({event_key,dismissed})),error:null})})}),rpc:async(name,args)=>{calls.push({name,args});if(fail)return{error:new Error('Offline')};for(const key of args.p_keys)rows.set(key,(rows.get(key)??false)||args.p_clear);return{error:null};}};
 const jsx=(type,props,key)=>({type,props:props??{},key});const module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react-dom'?{createPortal:x=>x}:name==='react/jsx-runtime'?{jsx,jsxs:jsx,Fragment:'fragment'}:name==='./db'?{supabase}:name==='./interactions.mjs'?{marketNotifications}:new Proxy({},{get:()=>()=>null}),document:{getElementById:()=>({})},window:{confirm:()=>true},Date,Set,console});
 const props={markets:[{id:'m',title:'Finished?',status:'resolved',outcome:'yes',resolved_at:'2026-10-31T10:00:00Z',closes_at:'2026-10-31T09:00:00Z'}],votes:[],userId:'member',admin:false,tick:0,refresh:()=>{},notify:()=>{},openMarket:()=>{}};
 const render=()=>{cursor=0;tree=module.exports.default(props);for(const fn of pending.splice(0))fn();return tree;};
 const walk=node=>!node||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(walk):[node,...walk(node.props?.children)];
 const text=node=>node==null||typeof node==='boolean'?'':typeof node!=='object'?String(node):Array.isArray(node)?node.map(text).join(''):text(node.props?.children);
 return{rows,calls,props,render,nodes:()=>walk(tree),button:label=>walk(tree).find(n=>n.type==='button'&&(n.props['aria-label']===label||text(n)===label)),badge:()=>walk(tree).find(n=>n.props?.className==='notification-badge'),text:()=>text(tree)};
}
test('opening notifications marks visible items read and immediately removes the badge',async()=>{
 const app=panel();app.render();await settle();app.render();assert.ok(app.badge());app.button('Notifications, 1 unread').props.onClick();await settle();app.render();assert.equal(app.badge(),undefined);assert.equal(app.calls[0].name,'acknowledge_notifications');assert.equal(app.calls[0].args.p_clear,false);assert.match(app.text(),/Finished\?/);
});
test('cleared notifications disappear, remain cleared on reload, and cannot be resurrected by marking read',async()=>{
 const app=panel();app.render();await settle();app.render();app.button('Notifications, 1 unread').props.onClick();await settle();app.render();app.button('Clear notifications').props.onClick();await settle();app.render();assert.equal(app.badge(),undefined);assert.match(app.text(),/No notifications/);assert.equal([...app.rows.values()][0],true);
 const reload=panel(app.rows);reload.render();await settle();reload.render();reload.button('Notifications').props.onClick();reload.render();assert.equal(reload.badge(),undefined);assert.match(reload.text(),/No notifications/);
});
test('failed acknowledgements restore unread badges instead of silently losing updates',async()=>{
 const app=panel(new Map(),true);app.render();await settle();app.render();app.button('Notifications, 1 unread').props.onClick();await settle();app.render();assert.ok(app.badge());assert.equal(app.rows.size,0);
});
