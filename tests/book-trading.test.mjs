import * as displayFormat from '../src/display-format.mjs';
import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import ts from 'typescript';
import {bookQuote} from '../src/trading-quote.mjs';
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
 vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/PositionSummary.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports:summaryModule.exports,require:name=>name==='./display-format.mjs'?displayFormat:({jsx:summaryJsx,jsxs:summaryJsx})});
 const jsx=(type,props,key)=>Object.values(summaryModule.exports).includes(type)?type(props):raw(type,props,key),module={exports:{}};
 vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./db'?{supabase}:name==='./display-format.mjs'?displayFormat:name==='./trading-quote.mjs'?{bookQuote}:name==='./position-preview.mjs'?positionMath:name==='./PositionSummary'?summaryModule.exports:name==='./math.mjs'?{quote,sharesForBudget,netPreview}:name==='./orderbook.mjs'?{quoteOrder,marketLimit}:name==='./quick-bet.mjs'?{automaticPrice,quantityForCredits,sellFraction}:name==='./interactions.mjs'?{requiresTradeConfirmation}:name==='./ending-times.mjs'?{schoolDateTime}:new Proxy({},{get:()=>()=>null}),Date,crypto:{randomUUID},sessionStorage:{getItem:()=>'',setItem(){}},document:{getElementById:()=>null},setInterval:()=>1,clearInterval(){}});
 const props={userId:'a',market:{id:'m',title:'A question?',execution_model:model,q_yes:0,q_no:0,liquidity:400,initial_probability:.5,status:'open',probability:.5,price_available:false,closes_at:new Date(Date.now()+3600000).toISOString()},side:'yes',setSide(s){props.side=s;},balance,positions,frozen:false,tick:0,refresh(){},notify:x=>messages.push(x)};
 const walk=node=>!node||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(walk):[node,...walk(node.props?.children)];
 const text=node=>node==null||typeof node==='boolean'?'':typeof node!=='object'?String(node):Array.isArray(node)?node.map(text).join(''):node.props?.['aria-hidden']?'':text(node.props?.children);
 const render=()=>{cursor=0;tree=module.exports.default(props);for(const effect of pending.splice(0))effect();};
 return{calls,messages,props,render,text:()=>text(tree),nodes:()=>walk(tree),button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label),submit:()=>walk(tree).find(n=>n.type==='button'&&n.props.className?.includes('trade-submit')),finish:()=>resolveFill()};
}
const start=async(options)=>{const app=trading(options);app.render();await settle();app.render();return app;};
const held=(side,shares,cost,reserved=0)=>({market_id:'m',side,shares,net_cost:cost,reserved_shares:reserved});
const sent=app=>app.calls.filter(c=>c.name==='execute_trade');
const selectMode=(app,mode)=>{app.field('Order type').props.onChange({target:{value:mode}});app.render();};
const action=(app,a,side)=>{app.button(a).props.onClick();app.render();app.nodes().find(n=>n.type==='button'&&n.key===side&&n.props.className?.includes('market-outcome')).props.onClick();app.render();};
const settings=app=>{app.nodes().find(n=>n.type==='details'&&n.props.className==='market-trade-settings').props.onToggle({currentTarget:{open:true}});app.render();};
test('separate Buy/Sell and Yes/No controls submit explicit budget buys',async()=>{
 const app=await start();assert.ok(app.button('Buy'));assert.ok(app.button('Sell'));assert.ok(app.field('Outcome'));assert.ok(app.field('Credits to spend'));
 selectMode(app,'limit');await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'buy');assert.equal(sent(app)[0].args.p_amount,25);assert.equal(sent(app)[0].args.p_side,'yes');assert.equal(sent(app)[0].args.p_price,.5);assert.equal(sent(app)[0].args.p_tif,'GTC');assert.equal('projection' in sent(app)[0].args,false);
});
test('empty book disables a market trade and offers an explicit limit order',async()=>{
 const app=await start();assert.equal(app.submit().props.disabled,true);assert.match(app.text(),/No sellers available/);await app.submit().props.onClick();assert.equal(sent(app).length,0);
 app.button('Place a limit order').props.onClick();app.render();assert.equal(app.submit().props.disabled,false);assert.match(app.text(),/50\.00 wait at your limit price/);
 app.field('Limit price per share').props.onChange({target:{value:'0'}});app.render();assert.equal(app.submit().props.disabled,true);
});
test('market buys use protected depth, a budget cap and FAK; successful submission clears the draft',async()=>{
 const app=await start({asks:[{price:.4,size:10},{price:.6,size:100}]});assert.equal(app.submit().props.disabled,false);await app.submit().props.onClick();await settle();app.render();
 assert.equal(sent(app)[0].args.p_tif,'FAK');assert.equal(sent(app)[0].args.p_price,.603);assert.equal(sent(app)[0].args.p_amount,25);assert.equal(app.field('Credits to spend').props.value,'');assert.equal(app.submit().props.disabled,true);
});
test('buying Yes preserves No holdings and requires actual available credits',async()=>{
 const app=await start({positions:[held('no',20,8)]});selectMode(app,'limit');assert.match(app.text(),/Your positions/);assert.match(app.text(),/50\.00 Yes · 20\.00 No/);assert.doesNotMatch(app.text(),/Reduces No|Switches|Clear position/);
 await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'buy');
 const empty=await start({balance:0,positions:[held('no',100,50)],model:'amm'});assert.equal(empty.submit().props.disabled,true);action(empty,'Sell','no');empty.button('Max').props.onClick();empty.render();assert.equal(empty.submit().props.disabled,false);
});
test('sell presets use only unreserved shares on the selected side',async()=>{
 const app=await start({model:'amm',positions:[held('yes',100,40,20),held('no',30,12)]});action(app,'Sell','yes');assert.equal(app.field('Credits to spend'),undefined);app.button('25%').props.onClick();app.render();assert.equal(app.field('Shares to sell').props.value,'20');assert.match(app.text(),/80\.00 Yes · 30\.00 No/);await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_action,'sell');assert.equal(sent(app)[0].args.p_amount,20);assert.ok(sent(app)[0].args.p_min_return>0);assert.equal(sent(app)[0].args.p_factor,1);assert.equal(app.calls.some(c=>c.name==='loss_summary'),false);
 const other=await start({model:'amm',positions:[held('yes',100,40,20),held('no',30,12)]});action(other,'Sell','yes');other.field('Shares to sell').props.onChange({target:{value:'81'}});other.render();assert.equal(other.submit().props.disabled,true);action(other,'Sell','no');other.button('Max').props.onClick();other.render();assert.equal(other.field('Shares to sell').props.value,'30');
});
test('selling without holdings, frozen accounts and closed markets cannot submit',async()=>{
 const app=await start({model:'amm'});action(app,'Sell','yes');assert.equal(app.submit().props.disabled,true);assert.match(app.text(),/No Yes shares available/);app.button('Buy').props.onClick();app.props.frozen=true;app.render();assert.equal(app.submit().props.disabled,true);app.props.frozen=false;app.props.market.closes_at=new Date(0).toISOString();app.render();assert.equal(app.submit().props.disabled,true);
});
test('position rows show independent basis, shares and direct sell actions',async()=>{
 const app=await start({positions:[held('yes',100,40),held('no',30,12)],bids:[{price:.6,size:200}]});assert.match(app.text(),/Your positions/);assert.match(app.text(),/100\.00 shares/);assert.match(app.text(),/30\.00 shares/);assert.match(app.text(),/◈ 40 paid/);assert.match(app.text(),/If YesTotal return◈ 100Profit \/ loss\+◈ 48/);app.field('Sell No position').props.onClick();app.render();assert.ok(app.field('Shares to sell'));assert.equal(app.submit().props.children,'Sell No');
});
test('leverage stays in settings and only applies to buys from flat',async()=>{
 const app=await start({balance:10,model:'amm'});assert.equal(app.button('5×'),undefined);settings(app);app.button('10×').props.onClick();app.field('Credits to spend').props.onChange({target:{value:'10'}});app.render();assert.equal(app.submit().props.disabled,false);await app.submit().props.onClick();await settle();app.render();assert.equal(sent(app).length,0);assert.match(app.text(),/Maximum loss◈ 100/);assert.ok(app.button('Confirm buy'));app.button('Cancel').props.onClick();action(app,'Sell','yes');assert.equal(app.button('10×'),undefined);
 const owned=await start({positions:[held('no',1,.5)]});settings(owned);assert.equal(owned.button('5×').props.disabled,true);
});
test('confirmation snapshots the action and prevents duplicate requests',async()=>{
 const app=await start({deferFill:true,positions:[held('yes',500,200)],bids:[{price:.5,size:1000}]});action(app,'Sell','yes');app.field('Shares to sell').props.onChange({target:{value:'200'}});app.render();await app.submit().props.onClick();await settle();app.render();const confirm=app.button('Confirm sell');assert.ok(confirm);action(app,'Buy','no');confirm.props.onClick();confirm.props.onClick();assert.equal(sent(app).length,1);assert.equal(sent(app)[0].args.p_action,'sell');assert.equal(sent(app)[0].args.p_side,'yes');assert.equal(sent(app)[0].args.p_amount,200);app.finish();await settle();
});
test('limit sells use the chosen minimum and duration while market sells use protected bids',async()=>{
 const app=await start({positions:[held('yes',20,8)],bids:[{price:.7,size:20}]});action(app,'Sell','yes');app.button('50%').props.onClick();app.render();assert.match(app.text(),/10\.00 shares can match now/);await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_price,.6965);assert.equal(sent(app)[0].args.p_tif,'FAK');assert.equal(sent(app)[0].args.p_amount,10);
 const limit=await start({positions:[held('yes',20,8)],bids:[{price:.7,size:20}]});action(limit,'Sell','yes');selectMode(limit,'limit');limit.button('50%').props.onClick();limit.render();limit.field('Order duration').props.onChange({target:{value:'FAK'}});limit.render();await limit.submit().props.onClick();await settle();assert.equal(sent(limit)[0].args.p_tif,'FAK');assert.equal(sent(limit)[0].args.p_price,.5);
});
test('AMM buy protects its quote and does not net opposite shares',async()=>{
 const app=await start({model:'amm',positions:[held('no',20,8)]});await app.submit().props.onClick();await settle();assert.equal(sent(app)[0].args.p_price,null);assert.ok(sent(app)[0].args.p_min_shares>0);assert.equal(sent(app)[0].args.p_amount,25);assert.equal(sent(app)[0].args.p_action,'buy');
});
test('buy previews remove cost, cash change and realised profit while sell previews keep realised profit',async()=>{
 const app=await start({model:'amm',positions:[held('yes',100.1234,40)]});
 assert.doesNotMatch(app.text(),/Est\. total cost|Cash change now|Profit realised now/);
 assert.match(app.text(),/100\.12 shares/);
 action(app,'Sell','yes');app.button('25%').props.onClick();app.render();
 assert.doesNotMatch(app.text(),/Cash change now|Trade settings/);assert.match(app.text(),/Profit realised now/);
});
test('selling hides Trade settings for every model and retains CLOB limit duration controls',async()=>{
 for(const model of ['amm','clob']){
  const app=await start({model,positions:[held('yes',20,8)]});settings(app);action(app,'Sell','yes');
  assert.equal(app.nodes().some(n=>n.type==='details'&&n.props.className==='market-trade-settings'),false);
  if(model==='clob'){selectMode(app,'limit');assert.ok(app.field('Order duration'));}
 }
});
test('confirmation is compact and never sends display metadata to the trade RPC',async()=>{
 const app=await start({model:'amm',balance:100});app.field('Credits to spend').props.onChange({target:{value:'50'}});app.render();await app.submit().props.onClick();await settle();app.render();
 assert.ok(app.button('Confirm buy'));assert.match(app.text(),/Estimated shares/);assert.doesNotMatch(app.text(),/Cash change now|Profit realised now/);
 await app.button('Confirm buy').props.onClick();await settle();assert.equal(sent(app).length,1);assert.equal('quote' in sent(app)[0].args,false);assert.equal('projection' in sent(app)[0].args,false);assert.equal(sent(app)[0].args.p_amount,50);
});
