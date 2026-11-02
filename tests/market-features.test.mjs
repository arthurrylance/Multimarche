import {randomUUID} from 'node:crypto';
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
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx,Fragment:'fragment'}:name==='./db'?{supabase}:name==='./ending-times.mjs'?{resolveEnding}:extra[name]??dummy,Date,crypto:{randomUUID},FormData:class{constructor(data){this.data=data;}get(key){return this.data[key];}}});
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
 const text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):text(n.props?.children);
 return {calls,props,render(){cursor=0;tree=module.exports[exportName](props);for(const e of pending.splice(0))e();},nodes:()=>walk(tree),text:()=>text(tree),button:label=>walk(tree).find(n=>n.type==='button'&&(text(n)===label||n.props['aria-label']===label)),form:()=>walk(tree).find(n=>n.type==='form')};
}
test('creation defaults to Automatic and sends the selected model with the existing rules and deadline',async()=>{
 const done=[],app=mount('App.tsx',{done:id=>done.push(id)},{exportName:'CreateForm',rpc:async()=>({data:'created'})});app.render();assert.equal(app.button('AMM — Automatic market maker').props['aria-pressed'],true);
 app.nodes().find(n=>n.props['aria-label']==='Starting likelihood of Yes').props.onChange({target:{value:'15'}});app.render();
 const data={title:'Question?',yes:'Happens',no:'Does not',verifications:'3'};await app.form().props.onSubmit({preventDefault(){},currentTarget:data});assert.equal(app.calls[0].name,'create_market_v7');assert.equal(app.calls[0].args.p_execution,'amm');assert.equal(app.calls[0].args.p_probability,.15);assert.equal(app.calls[0].args.p_verifications,3);assert.ok(Date.parse(app.calls[0].args.p_closes)>Date.now());
 app.button('CLOB — Order book').props.onClick();app.render();await app.form().props.onSubmit({preventDefault(){},currentTarget:data});assert.equal(app.calls[1].args.p_execution,'clob');assert.equal(done.length,2);
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

test('grouped creation keeps option drafts, sends independent meanings and reuses the same request after an uncertain failure',async()=>{
 const done=[];let attempt=0;const app=mount('App.tsx',{done:id=>done.push(id)},{exportName:'CreateForm',rpc:async()=>++attempt===1?{error:new Error('Temporary connection failure')}:{data:{group_id:'g',market_ids:['child-a','child-b']}}});app.render();app.button('Several options').props.onClick();app.render();
 const option=i=>app.nodes().find(n=>n.type==='textarea'&&n.props['aria-label']===`Option ${i}`);
 option(1).props.onChange({target:{value:'Says etcetera'}});option(2).props.onChange({target:{value:'Old draft'}});app.render();app.button('Add option').props.onClick();app.render();option(3).props.onChange({target:{value:'Mentions homework'}});app.render();app.button('Remove option 2').props.onClick();app.render();assert.equal(option(2).props.value,'Mentions homework');
 const data={title:'What happens in physics?',verifications:'2'};await app.form().props.onSubmit({preventDefault(){},currentTarget:data});app.render();assert.match(app.text(),/Temporary connection failure/);await app.form().props.onSubmit({preventDefault(){},currentTarget:data});
 assert.equal(app.calls[0].name,'create_market_group_v2');assert.equal(JSON.stringify(app.calls[0].args),JSON.stringify(app.calls[1].args));assert.deepEqual(Array.from(app.calls[0].args.p_options,o=>o.label),['Says etcetera','Mentions homework']);assert.equal(app.calls[0].args.p_execution,'amm');assert.equal(app.calls[0].args.p_probability,.5);assert.equal(done[0],'child-a');assert.match(app.text(),/More than one can happen/);
});
test('group cards and sibling navigation open the exact option and side, preserving independent prices',()=>{
 const options=[{id:'a',title:'Physics · A',option_label:'A',probability:.75,status:'open',closes_at:'2099-01-01T12:00:00Z',volume:1},{id:'b',title:'Physics · B',option_label:'B',probability:.8,status:'open',closes_at:'2099-01-01T12:00:00Z',volume:2}],opened=[],stars=[];
 const app=mount('GroupMarket.tsx',{listing:{title:'Physics',markets:options,openId:'a',volume:3,closesAt:Date.parse(options[0].closes_at)},open:(...args)=>opened.push(args),watched:[],watch:id=>stars.push(id)},{exportName:'GroupMarketCard'});app.render();assert.match(app.text(),/75%/);const tabs=app.nodes().find(n=>n.props.label==='Predictions in Physics');assert.equal(tabs.props.options.length,2);assert.equal(app.nodes().filter(n=>n.type==='button'&&n.props.children==='No').length,1);tabs.props.select('b');app.render();assert.match(app.text(),/80%/);app.nodes().find(n=>n.type==='button'&&n.props.children==='No').props.onClick();assert.deepEqual(opened[0],['b','no']);app.button('Star B').props.onClick();assert.equal(stars[0],'b');
 const nav=mount('GroupMarket.tsx',{title:'Physics',markets:options,selected:'a',open:id=>opened.push([id]),back(){}},{exportName:'GroupNavigator'});nav.render();const second=nav.nodes().find(n=>n.type==='button'&&n.key==='b');second.props.onClick();assert.deepEqual(opened[1],['b']);
});
test('admin money reset needs exact typed confirmation and acknowledgement and reuses failed request',async()=>{
 let attempt=0;const events=[],app=mount('AdminMoneyReset.tsx',{disabled:false,onBusyChange:v=>events.push(v),refresh(){},notify(){}},{rpc:async()=>++attempt===1?{error:new Error('Retry')}:{data:{}}});app.render();const submit=()=>app.form().props.onSubmit({preventDefault(){}});
 await submit();assert.equal(app.calls.length,0);app.nodes().find(n=>n.props['aria-label']==='Reset confirmation').props.onChange({target:{value:'RESET ALL'}});app.render();await submit();assert.equal(app.calls.length,0);app.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.onChange({target:{checked:true}});app.render();await submit();app.render();await submit();assert.equal(app.calls.length,2);assert.equal(app.calls[0].args.p_request,app.calls[1].args.p_request);app.render();assert.match(app.text(),/Reset complete/);assert.equal(app.nodes().find(n=>n.props['aria-label']==='Reset confirmation').props.value,'');
});
test('market card whitespace opens the market while buttons keep their own actions',()=>{
 const opened=[],stars=[],market={id:'tile',title:'Click the tile',probability:.5,volume:0,status:'open',execution_model:'amm',closes_at:new Date(Date.now()+3600000).toISOString()};
 const app=mount('App.tsx',{market,open:(...args)=>opened.push(args),watched:false,watch:()=>stars.push(true)},{exportName:'MarketCard'});app.render();const article=app.nodes().find(n=>n.type==='article');article.props.onClick({target:{closest:()=>null}});assert.equal(opened.length,1);assert.equal(opened[0][0],'tile');
 const star=app.nodes().find(n=>n.props['aria-label']==='Star market');star.props.onClick();article.props.onClick({target:{closest:()=>({})}});assert.equal(stars.length,1);assert.equal(opened.length,1);
 const yes=app.nodes().find(n=>n.type==='button'&&n.props.className==='yes-button');yes.props.onClick();article.props.onClick({target:{closest:()=>({})}});assert.equal(opened.length,2);assert.equal(opened[1][1],'yes');
});
