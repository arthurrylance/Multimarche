import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';
import {resolveEnding} from '../src/ending-times.mjs';import {avatarPath} from '../src/avatar.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function mount(file,props,{exportName='default',rpc=async()=>({data:'proposed'}),extra={}}={}){
 const compiled=ts.transpileModule(readFileSync(new URL(`../src/${file}`,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
 const state=[],effects=[],pending=[],calls=[];let cursor=0,tree;
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],v=>{state[i]=typeof v==='function'?v(state[i]):v;}];},useRef:init=>{const i=cursor++;return state[i]??={current:init};},useCallback:fn=>{cursor++;return fn;},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i].deps[j])){effects[i]={deps};pending.push(fn);}},lazy:()=>()=>null};
 const supabase={rpc:async(name,args)=>{calls.push({name,args});return rpc(name,args);}};
 const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};
 const dummy=new Proxy({},{get:()=>()=>null});
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx,Fragment:'fragment'}:name==='./db'?{supabase}:name==='./ending-times.mjs'?{resolveEnding}:extra[name]??dummy,Date,FormData:class{constructor(data){this.data=data;}get(key){return this.data[key];}}});
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
 const text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):text(n.props?.children);
 return {calls,props,render(){cursor=0;tree=module.exports[exportName](props);for(const e of pending.splice(0))e();},nodes:()=>walk(tree),text:()=>text(tree),button:label=>walk(tree).find(n=>n.type==='button'&&(text(n)===label||n.props['aria-label']===label)),form:()=>walk(tree).find(n=>n.type==='form')};
}
test('creation defaults to Automatic and sends the selected model with the existing rules and deadline',async()=>{
 const done=[],app=mount('App.tsx',{done:id=>done.push(id)},{exportName:'CreateForm',rpc:async()=>({data:'created'})});app.render();assert.equal(app.nodes().find(n=>n.type==='input'&&n.props.value==='amm').props.checked,true);
 const data={title:'Question?',yes:'Happens',no:'Does not',verifications:'3'};await app.form().props.onSubmit({preventDefault(){},currentTarget:data});assert.equal(app.calls[0].name,'create_market_v6');assert.equal(app.calls[0].args.p_execution,'amm');assert.equal(app.calls[0].args.p_verifications,3);assert.ok(Date.parse(app.calls[0].args.p_closes)>Date.now());
 app.nodes().find(n=>n.type==='input'&&n.props.value==='clob').props.onChange();app.render();await app.form().props.onSubmit({preventDefault(){},currentTarget:data});assert.equal(app.calls[1].args.p_execution,'clob');assert.equal(done.length,2);
});
const market={id:'m',status:'proposed',outcome:'yes',required_verifications:2},vote={market_id:'m',user_id:'a',outcome:'yes',evidence:'Observed'};
function resolution(props={},rpc){const messages=[];const app=mount('ResolutionPanel.tsx',{market:{...market},votes:[vote],userId:'b',admin:false,frozen:false,name:id=>id,refresh(){},notify:s=>messages.push(s),...props},{rpc});return{app,messages};}
test('an ordinary member can disagree with proposed Yes, without their selection being forced back to Yes',async()=>{
 const{app,messages}=resolution({},async()=>({data:'disputed'}));app.render();app.button('No, it didn’t').props.onClick();app.render();const select=app.nodes().find(n=>n.type==='select');assert.equal(select.props.value,'no');assert.ok(!select.props.disabled);await app.form().props.onSubmit({preventDefault(){}});assert.equal(app.calls[0].name,'resolve_market');assert.equal(app.calls[0].args.p_outcome,'no');assert.match(messages[0],/Disagreement recorded/);
});
test('disputed results show counts, allow changing or withdrawing one own vote, and respect timeouts',async()=>{
 const mine={...vote,user_id:'b',outcome:'no'},app=resolution({market:{...market,outcome:null,resolution_disputed:true},votes:[vote,mine]},async()=>({data:'resolved'})).app;app.render();assert.match(app.text(),/Result disputed/);assert.match(app.text(),/Yes 1No 1Void 0/);app.button('Change my vote').props.onClick();app.render();app.nodes().find(n=>n.type==='select').props.onChange({target:{value:'yes'}});app.render();await app.form().props.onSubmit({preventDefault(){}});assert.equal(app.calls[0].args.p_outcome,'yes');app.render();await app.button('Withdraw my vote').props.onClick();assert.equal(app.calls[1].name,'withdraw_resolution');app.props.frozen=true;app.render();assert.equal(app.button('Change my vote').props.disabled,true);assert.equal(app.button('Withdraw my vote').props.disabled,true);
});
test('profile reroll saves only the own-account picture, without submitting nickname or password changes',async()=>{
 function Avatar(){}const messages=[],app=mount('AccountPage.tsx',{profile:{id:'b',username:'member',nickname:'Member',avatar_color:null},refresh(){},notify:s=>messages.push(s)},{rpc:async()=>({data:'green'}),extra:{'./Avatar':{default:Avatar}}});app.render();assert.equal(app.button('Randomize profile picture').props.type,'button');app.button('Randomize profile picture').props.onClick();await settle();app.render();assert.equal(app.calls[0].name,'randomize_avatar');assert.equal(app.calls[0].args,undefined);assert.equal(app.nodes().find(n=>n.type===Avatar).props.color,'green');assert.match(messages[0],/Picture changed/);
 app.props.profile={...app.props.profile,avatar_color:'red'};app.render();app.render();assert.equal(app.nodes().find(n=>n.type===Avatar).props.color,'red');
});
test('saved avatar colours override the stable default and invalid paths cannot become image URLs',()=>{
 const id='account';assert.equal(avatarPath(id,'green'),'/avatars/green.png');assert.equal(avatarPath(id,'https://other.invalid/image'),avatarPath(id));assert.equal(avatarPath(id,null),avatarPath(id));
});
