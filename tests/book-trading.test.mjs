import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import ts from 'typescript';
import {automaticPrice,quantityForCredits,sellFraction} from '../src/quick-bet.mjs';
import {quote,sharesForBudget,netPreview} from '../src/math.mjs';
import {quoteOrder,marketLimit} from '../src/orderbook.mjs';import {requiresTradeConfirmation} from '../src/interactions.mjs';import {schoolDateTime} from '../src/ending-times.mjs';
const compiled=ts.transpileModule(readFileSync(new URL('../src/BookTrading.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function trading({asks=[],positions=[],balance=1000,deferFill=false,loan=null,model='clob'}={}){
 const state=[],effects=[],pending=[],calls=[],messages=[];let cursor=0,tree,resolveFill;
 const hooks={useState:init=>{const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;return[state[i],v=>{state[i]=typeof v==='function'?v(state[i]):v;}];},useRef:init=>{const i=cursor++;return state[i]??={current:init};},useCallback:fn=>{cursor++;return fn;},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i].deps[j])){effects[i]={deps};pending.push(fn);}}};
 const snapshot={bids:{yes:[],no:[]},asks:{yes:asks,no:[]},executable_bids:{yes:[],no:[]},executable_asks:{yes:asks,no:[]},orders:[]};
 const chain={select:()=>chain,eq:()=>chain,maybeSingle:async()=>({data:loan})};
 const supabase={from:()=>chain,rpc:async(name,args)=>{calls.push({name,args});if(name==='orderbook')return{data:snapshot};if(name==='loss_summary')return{data:{triggered:false}};if(name==='predict'){if(deferFill)await new Promise(r=>{resolveFill=r;});return{data:{status:'open',filled:0,remaining:args.p_budget/args.p_price,price:args.p_price}};}return{};}};
 const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./db'?{supabase}:name==='./math.mjs'?{quote,sharesForBudget,netPreview}:name==='./orderbook.mjs'?{quoteOrder,marketLimit}:name==='./quick-bet.mjs'?{automaticPrice,quantityForCredits,sellFraction}:name==='./interactions.mjs'?{requiresTradeConfirmation}:name==='./ending-times.mjs'?{schoolDateTime}:new Proxy({},{get:()=>()=>null}),Date,crypto:{randomUUID},sessionStorage:{getItem:()=>'',setItem(){}},setInterval:()=>1,clearInterval(){}});
 const props={userId:'a',market:{id:'m',title:'A question?',execution_model:model,q_yes:0,q_no:0,liquidity:400,initial_probability:.5,status:'open',probability:.5,price_available:false,closes_at:new Date(Date.now()+3600000).toISOString()},side:'yes',setSide(){},balance,positions,frozen:false,tick:0,refresh(){},notify:x=>messages.push(x)};
 const walk=node=>!node||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(walk):[node,...walk(node.props?.children)];
 const text=node=>node==null||typeof node==='boolean'?'':typeof node!=='object'?String(node):Array.isArray(node)?node.map(text).join(''):node.props?.['aria-hidden']?'':text(node.props?.children);
 const render=()=>{cursor=0;tree=module.exports.default(props);for(const effect of pending.splice(0))effect();};
 return{calls,messages,props,render,text:()=>text(tree),nodes:()=>walk(tree),button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label),submit:()=>walk(tree).find(n=>n.type==='button'&&n.props.className?.includes('trade-submit')),finish:()=>resolveFill()};
}
test('simple prediction only asks for direction and credits; no shares or cash-out controls',async()=>{
 const app=trading();app.render();await settle();app.render();assert.ok(app.field('Credits to bet'));assert.equal(app.button('Cash out'),undefined);assert.equal(app.button('Sell'),undefined);assert.equal(app.field('Order quantity in shares'),undefined);assert.equal(app.submit().props.disabled,false);
 await app.submit().props.onClick();await settle();const order=app.calls.find(c=>c.name==='predict');assert.equal(order.args.p_price,.5);assert.equal(order.args.p_budget,25);assert.equal(order.args.p_factor,1);assert.equal(order.args.p_tif,'GTC');assert.match(app.messages[0],/Unmatched/);
});
test('simple book predictions choose best executable price and leave matching to the server',async()=>{
 const app=trading({asks:[{price:.75,size:20},{price:.65,size:1}]});app.render();await settle();app.render();app.field('Credits to bet').props.onChange({target:{value:'10'}});app.render();await app.submit().props.onClick();await settle();const order=app.calls.find(c=>c.name==='predict');assert.equal(order.args.p_price,.65);assert.equal(order.args.p_budget,10);assert.equal('p_quantity' in order.args,false);
});
test('positions are hidden by default and rounded in Advanced; netting preview stays correct',async()=>{
 const app=trading({positions:[{market_id:'m',side:'no',shares:20.205,net_cost:8}]});app.render();await settle();app.render();assert.doesNotMatch(app.text(),/Your bet|Backing No|20.205|Leverage|Net result/);assert.equal(app.button('5×'),undefined);
 app.button('Advanced').props.onClick();app.render();assert.match(app.text(),/Backing No/);assert.match(app.text(),/20 potential payout/);assert.doesNotMatch(app.text(),/20.205/);
 app.field('Credits to bet').props.onChange({target:{value:'5'}});app.render();assert.match(app.text(),/After this betNo · ◈ 10/);app.field('Credits to bet').props.onChange({target:{value:'15'}});app.render();assert.match(app.text(),/After this betYes · ◈ 10/);
});
test('zero available cash can still reduce an opposite position',async()=>{
 const app=trading({balance:0,positions:[{market_id:'m',side:'no',shares:100,net_cost:50}]});app.render();await settle();app.render();assert.equal(app.submit().props.disabled,false);await app.submit().props.onClick();await settle();assert.equal(app.calls.filter(c=>c.name==='predict').length,1);app.props.frozen=true;app.render();assert.equal(app.submit().props.disabled,true);
});
test('leverage lives in Advanced, requires only the stake, and warns about negative balances',async()=>{
 const app=trading({balance:10});app.render();await settle();app.render();app.button('Advanced').props.onClick();app.render();app.button('10×').props.onClick();app.field('Credits to bet').props.onChange({target:{value:'10'}});app.render();assert.equal(app.submit().props.disabled,false);assert.match(app.text(),/can leave your balance negative/);await app.submit().props.onClick();await settle();app.render();assert.equal(app.calls.filter(c=>c.name==='predict').length,0);assert.match(app.text(),/Maximum loss◈ 100/);assert.match(app.text(),/Return if correct and matched◈ 110/);assert.ok(app.button('Confirm'));
 const held=trading({positions:[{market_id:'m',side:'yes',shares:1,net_cost:.5}]});held.render();await settle();held.render();held.button('Advanced').props.onClick();held.render();assert.equal(held.button('5×').props.disabled,true);
 const borrowed=trading({loan:{market_id:'another',factor:5,remaining:40}});borrowed.render();await settle();borrowed.render();borrowed.button('Advanced').props.onClick();borrowed.render();assert.equal(borrowed.button('10×').props.disabled,true);
});
test('large confirmation captures direction, amount and multiplier and prevents duplicate submission',async()=>{
 const app=trading({deferFill:true});app.render();await settle();app.render();app.field('Credits to bet').props.onChange({target:{value:'100'}});app.render();await app.submit().props.onClick();await settle();app.render();const confirm=app.button('Confirm');assert.ok(confirm);app.field('Credits to bet').props.onChange({target:{value:'10'}});app.render();confirm.props.onClick();confirm.props.onClick();const orders=app.calls.filter(c=>c.name==='predict');assert.equal(orders.length,1);assert.equal(orders[0].args.p_budget,100);assert.equal(orders[0].args.p_price,.5);app.finish();await settle();
});
test('advanced retains manual price, expiry and immediate execution without separate shares or sell form',async()=>{
 const app=trading();app.render();await settle();app.render();app.button('Advanced').props.onClick();app.render();app.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.onChange({target:{checked:true}});app.render();app.field('Limit price per share').props.onChange({target:{value:'.4'}});app.nodes().find(n=>n.type==='select').props.onChange({target:{value:'FOK'}});app.render();await app.submit().props.onClick();await settle();const order=app.calls.find(c=>c.name==='predict');assert.equal(order.args.p_price,.4);assert.equal(order.args.p_tif,'FOK');assert.equal(app.button('Sell'),undefined);
});
test('automatic uses same direction interface and protects the reviewed weighted quote',async()=>{
 const app=trading({model:'amm'});app.props.market.initial_probability=.1;app.props.market.probability=.1;app.render();await settle();app.render();assert.ok(app.button('Advanced'));assert.equal(app.button('5×'),undefined);await app.submit().props.onClick();await settle();const order=app.calls.find(c=>c.name==='predict');assert.equal(order.args.p_price,null);assert.ok(order.args.p_min_shares>100);assert.equal(order.args.p_budget,25);
});

test('simple view contains only amount and return/profit, and Advanced does not change the automatic price',async()=>{
 const app=trading({asks:[{price:.65,size:100}]});app.render();await settle();app.render();assert.equal(app.nodes().filter(n=>n.type==='input').length,1);assert.match(app.text(),/To win if Yes/);assert.match(app.text(),/Profit/);assert.doesNotMatch(app.text(),/Direction amount|Your position|Position after|reduces your|Leverage|No fees|0.5%|Quantity/);
 app.button('Advanced').props.onClick();app.render();assert.equal(app.field('Limit price per share'),undefined);app.button('Hide advanced').props.onClick();app.render();await app.submit().props.onClick();await settle();assert.equal(app.calls.find(c=>c.name==='predict').args.p_price,.65);
});
