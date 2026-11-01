import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import ts from 'typescript';
import {automaticPrice,quantityForCredits,sellFraction} from '../src/quick-bet.mjs';
import {quote,sharesForBudget,netPreview} from '../src/math.mjs';
import * as positionMath from '../src/position-preview.mjs';
import {quoteOrder,marketLimit} from '../src/orderbook.mjs';import {requiresTradeConfirmation} from '../src/interactions.mjs';import {schoolDateTime} from '../src/ending-times.mjs';
const compiled=ts.transpileModule(readFileSync(new URL('../src/BookTrading.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function trading({asks=[],positions=[],balance=1000,deferFill=false,loan=null,model='clob',orders=[],bids=[]}={}){
 const state=[],effects=[],pending=[],calls=[],messages=[];let cursor=0,tree,resolveFill;
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],v=>{state[i]=typeof v==='function'?v(state[i]):v;}];},useRef:init=>{const i=cursor++;return state[i]??={current:init};},useCallback:fn=>{cursor++;return fn;},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i].deps[j])){effects[i]={deps};pending.push(fn);}}};
 const snapshot={bids:{yes:[],no:[]},asks:{yes:asks,no:[]},executable_bids:{yes:bids,no:bids},executable_asks:{yes:asks,no:[]},orders};
 const chain={select:()=>chain,eq:()=>chain,maybeSingle:async()=>({data:loan})};
 const supabase={from:()=>chain,rpc:async(name,args)=>{calls.push({name,args});if(name==='orderbook')return{data:snapshot};if(name==='loss_summary')return{data:{triggered:false}};if(name==='position_accounting')return{data:{yes:positions.filter(p=>p.side==='yes').reduce((sum,p)=>sum+Number(p.net_cost||0),0),no:positions.filter(p=>p.side==='no').reduce((sum,p)=>sum+Number(p.net_cost||0),0)}};if(name==='execute_trade'){if(deferFill)await new Promise(r=>{resolveFill=r;});return{data:{status:'open',filled:0,remaining:args.p_amount/args.p_price,price:args.p_price}};}return{};}};
 const summaryModule={exports:{}},raw=(type,props,key)=>({type,props:props??{},key});
 const summaryJsx=(type,props,key)=>typeof type==='function'?type(props):raw(type,props,key);
 vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/PositionSummary.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports:summaryModule.exports,require:()=>({jsx:summaryJsx,jsxs:summaryJsx})});
 const jsx=(type,props,key)=>Object.values(summaryModule.exports).includes(type)?type(props):raw(type,props,key),module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./db'?{supabase}:name==='./position-preview.mjs'?positionMath:name==='./PositionSummary'?summaryModule.exports:name==='./math.mjs'?{quote,sharesForBudget,netPreview}:name==='./orderbook.mjs'?{quoteOrder,marketLimit}:name==='./quick-bet.mjs'?{automaticPrice,quantityForCredits,sellFraction}:name==='./interactions.mjs'?{requiresTradeConfirmation}:name==='./ending-times.mjs'?{schoolDateTime}:new Proxy({},{get:()=>()=>null}),Date,crypto:{randomUUID},sessionStorage:{getItem:()=>'',setItem(){}},setInterval:()=>1,clearInterval(){}});
 const props={userId:'a',market:{id:'m',title:'A question?',execution_model:model,q_yes:0,q_no:0,liquidity:400,initial_probability:.5,status:'open',probability:.5,price_available:false,closes_at:new Date(Date.now()+3600000).toISOString()},side:'yes',setSide(s){props.side=s;},balance,positions,frozen:false,tick:0,refresh(){},notify:x=>messages.push(x)};
 const walk=node=>!node||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(walk):[node,...walk(node.props?.children)];
 const text=node=>node==null||typeof node==='boolean'?'':typeof node!=='object'?String(node):Array.isArray(node)?node.map(text).join(''):node.props?.['aria-hidden']?'':text(node.props?.children);
 const render=()=>{cursor=0;tree=module.exports.default(props);for(const effect of pending.splice(0))effect();};
 return{calls,messages,props,render,text:()=>text(tree),nodes:()=>walk(tree),button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label),submit:()=>walk(tree).find(n=>n.type==='button'&&n.props.className?.includes('trade-submit')),finish:()=>resolveFill()};
}
const start=async(options)=>{const app=trading(options);app.render();await settle();app.render();return app;};
const held=(side,shares,cost,reserved=0)=>({market_id:'m',side,shares,net_cost:cost,reserved_shares:reserved});
const sent=app=>app.calls.filter(c=>c.name==='execute_trade');
test('all four independent actions are visible and buying uses a credit budget',async()=>{
 const app=await start();for(const label of ['Buy Yes','Buy No','Sell Yes','Sell No'])assert.ok(app.button(label));assert.ok(app.field('Credits to bet'));assert.equal(app.field('Clear position'),undefined);
 await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'buy');assert.equal(sent(app)[0].args.p_amount,25);assert.equal(sent(app)[0].args.p_side,'yes');assert.equal(sent(app)[0].args.p_price,.5);assert.equal('projection' in sent(app)[0].args,false);
});
test('buying Yes preserves No holdings and needs actual credits',async()=>{
 const app=await start({positions:[held('no',20,8)]});assert.match(app.text(),/Your holdings/);assert.match(app.text(),/50 Yes · 20 No/);assert.doesNotMatch(app.text(),/Reduces No|Switches|Clear position/);
 await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'buy');
 const empty=await start({balance:0,positions:[held('no',100,50)]});assert.equal(empty.submit().props.disabled,true);empty.button('Sell No').props.onClick();empty.render();empty.button('100%').props.onClick();empty.render();assert.equal(empty.submit().props.disabled,false);
});
test('sell selects only owned unreserved shares and never submits a buy',async()=>{
 const app=await start({model:'amm',positions:[held('yes',100,40,20),held('no',30,12)]});app.button('Sell Yes').props.onClick();app.render();assert.equal(app.field('Credits to bet'),undefined);assert.ok(app.field('Shares to sell'));app.button('25%').props.onClick();app.render();assert.equal(app.field('Shares to sell').props.value,'20');assert.match(app.text(),/80 Yes · 30 No/);await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'sell');assert.equal(sent(app)[0].args.p_amount,20);assert.ok(sent(app)[0].args.p_min_return>0);assert.equal(sent(app)[0].args.p_factor,1);assert.equal(app.calls.some(c=>c.name==='loss_summary'),false);
 app.field('Shares to sell').props.onChange({target:{value:'81'}});app.render();assert.equal(app.submit().props.disabled,true);
 app.button('Sell No').props.onClick();app.render();app.button('100%').props.onClick();app.render();assert.equal(app.field('Shares to sell').props.value,'30');
});
test('selling a side without holdings is disabled, as are frozen and closed trades',async()=>{
 const app=await start();app.button('Sell Yes').props.onClick();app.render();assert.equal(app.submit().props.disabled,true);assert.match(app.text(),/No Yes shares available/);app.button('Buy Yes').props.onClick();app.props.frozen=true;app.render();assert.equal(app.submit().props.disabled,true);app.props.frozen=false;app.props.market.closes_at=new Date(0).toISOString();app.render();assert.equal(app.submit().props.disabled,true);
});
test('both holdings and combined outcomes stay above the controls',async()=>{
 const app=await start({positions:[held('yes',100,40),held('no',30,12)],bids:[{price:.6,size:200}]});const text=app.text();assert.ok(text.indexOf('Your holdings')<text.indexOf('Place a bet'));assert.match(text,/Shares owned 100/);assert.match(text,/Shares owned 30/);assert.match(text,/If YesTotal return◈ 100Profit \/ loss\+◈ 48/);assert.match(text,/If NoTotal return◈ 30Profit \/ loss−◈ 22/);
});
test('leverage stays advanced, only on buys and only from flat',async()=>{
 const app=await start({balance:10});assert.equal(app.button('5×'),undefined);app.button('Advanced').props.onClick();app.render();app.button('10×').props.onClick();app.field('Credits to bet').props.onChange({target:{value:'10'}});app.render();assert.equal(app.submit().props.disabled,false);await app.submit().props.onClick();await settle();app.render();assert.equal(sent(app).length,0);assert.match(app.text(),/Maximum loss◈ 100/);assert.ok(app.button('Confirm'));app.button('Cancel').props.onClick();app.button('Sell Yes').props.onClick();app.render();assert.equal(app.button('10×'),undefined);
 const owned=await start({positions:[held('no',1,.5)]});owned.button('Advanced').props.onClick();owned.render();assert.equal(owned.button('5×').props.disabled,true);
});
test('confirmation snapshots action and shares and prevents duplicate requests',async()=>{
 const app=await start({deferFill:true,positions:[held('yes',500,200)],bids:[{price:.5,size:1000}]});app.button('Sell Yes').props.onClick();app.render();app.field('Shares to sell').props.onChange({target:{value:'200'}});app.render();await app.submit().props.onClick();await settle();app.render();const confirm=app.button('Confirm');assert.ok(confirm);app.button('Buy No').props.onClick();app.render();confirm.props.onClick();confirm.props.onClick();assert.equal(sent(app).length,1);assert.equal(sent(app)[0].args.p_action,'sell');assert.equal(sent(app)[0].args.p_side,'yes');assert.equal(sent(app)[0].args.p_amount,200);app.finish();await settle();
});
test('order-book sells use bids, allow limit/expiry controls and keep pending orders',async()=>{
 const app=await start({positions:[held('yes',20,8)],bids:[{price:.7,size:20}]});app.button('Sell Yes').props.onClick();app.render();app.button('50%').props.onClick();app.render();app.button('Advanced').props.onClick();app.render();assert.match(app.text(),/can match now/);app.nodes().find(n=>n.type==='select').props.onChange({target:{value:'FAK'}});app.render();await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_price,.7);assert.equal(sent(app)[0].args.p_tif,'FAK');assert.equal(sent(app)[0].args.p_amount,10);assert.doesNotMatch(app.text(),/replaces your pending/);
});
test('AMM buy protects the reviewed quote and does not net opposite shares',async()=>{
 const app=await start({model:'amm',positions:[held('no',20,8)]});await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_price,null);assert.ok(sent(app)[0].args.p_min_shares>0);assert.equal(sent(app)[0].args.p_amount,25);assert.equal(sent(app)[0].args.p_action,'buy');
});
