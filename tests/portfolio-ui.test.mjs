import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import ts from 'typescript';
import * as summary from '../src/portfolio-summary.mjs';import * as format from '../src/display-format.mjs';import * as countdown from '../src/bet-summary.mjs';
const compile=file=>ts.transpileModule(readFileSync(new URL(`../src/${file}`,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function mount(file,props){
 const instances=new Map(),modules={};let current,cursor,tree,path;
 const hooks={useState:init=>{const i=cursor++,instance=current;if(!(i in instance))instance[i]=typeof init==='function'?init():init;return[instance[i],v=>instance[i]=typeof v==='function'?v(instance[i]):v];},useRef:init=>{const i=cursor++;return current[i]??={current:init};},useEffect(){cursor++;}};
 const raw=(type,props,key)=>({type,props:props??{},key});
 const load=file=>{if(modules[file])return modules[file];const module={exports:{}};modules[file]=module.exports;vm.runInNewContext(compile(file),{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx:raw,jsxs:raw}:name==='./portfolio-summary.mjs'?summary:name==='./display-format.mjs'?format:name==='./bet-summary.mjs'?countdown:name.startsWith('./')?load(name.slice(2)+'.tsx'):new Proxy({},{get:()=>()=>null}),Date,setInterval:()=>1,clearInterval(){}});return module.exports;};
 const renderNode=(node,location)=>{if(!node||typeof node!=='object')return node;if(Array.isArray(node))return node.map((n,i)=>renderNode(n,`${location}/${n?.key??i}`));if(typeof node.type==='function'){const previous=current,previousCursor=cursor;path=location;current=instances.get(path)??[];instances.set(path,current);cursor=0;const next=renderNode(node.type(node.props),location+'/child');current=previous;cursor=previousCursor;return next;}return{...node,props:{...node.props,children:renderNode(node.props.children,location+'/children')}};};
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
 const text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):text(n.props?.children);
 const Component=load(file).default;
 return{props,render(){tree=renderNode(raw(Component,props),'root');},nodes:()=>walk(tree),text:()=>text(tree),button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label)};
}
const market=(id,extra={})=>({id,title:id,status:'open',probability:.6,closes_at:'2099-11-04',...extra});
const rows=()=>summary.positionSummaries([market('a',{group_id:'g',group_title:'Weekly words',option_label:'Level 7',group_position:0}),market('b',{group_id:'g',group_title:'Weekly words',option_label:'Homework',group_position:1}),market('solo'),market('done',{status:'resolved',outcome:'yes'})],[{market_id:'a',side:'yes',shares:10},{market_id:'b',side:'no',shares:5},{market_id:'solo',side:'yes',shares:20},{market_id:'done',side:'yes',shares:3}],{a:{yes:4,no:0},b:{yes:0,no:3},solo:{yes:10,no:0}});
test('portfolio defaults to open positions, filters settled/all, searches, and keeps open-only summary widgets',()=>{
 const opened=[],app=mount('PortfolioPositions.tsx',{rows:rows(),openMarket:(...args)=>opened.push(args),error:''});app.render();assert.equal(app.button('Open').props['aria-pressed'],true);assert.doesNotMatch(app.text(),/Settled · YES/);assert.match(app.text(),/Invested in open positions◈ 17/);assert.match(app.text(),/Potential payout◈ 35/);assert.match(app.text(),/Potential profit\+◈ 18/);assert.match(app.text(),/Potential return\+105.88%/);assert.doesNotMatch(app.text(),/Estimated current profit|Current value|Profit \/ loss \(est/);
 assert.equal(app.nodes().filter(n=>n.type==='article').length,2);
 app.button('Settled').props.onClick();app.render();assert.match(app.text(),/Settled · YES/);assert.equal(app.nodes().filter(n=>n.type==='article').length,1);assert.match(app.text(),/Invested in open positions◈ 17/);
 app.button('All').props.onClick();app.render();assert.equal(app.nodes().filter(n=>n.type==='article').length,3);
 app.field('Search your positions').props.onChange({target:{value:'Homework'}});app.render();assert.equal(app.nodes().filter(n=>n.type==='article').length,1);assert.match(app.text(),/5.00 shares/);app.button('Homework').props.onClick();assert.deepEqual(opened[0],['b','no']);
 app.field('Search your positions').props.onChange({target:{value:'absent'}});app.render();assert.match(app.text(),/No matching positions/);
});
test('homepage renders one card per grouped market and tabs open the exact held prediction and side',()=>{
 const opened=[],app=mount('ActiveBets.tsx',{rows:rows(),portfolio(){},openMarket:(...args)=>opened.push(args)});app.render();assert.equal(app.nodes().filter(n=>n.type==='article').length,2);assert.doesNotMatch(app.text(),/Settled ·/);
 const tabs=app.nodes().filter(n=>n.props.role==='tab');assert.equal(tabs.length,2);tabs[1].props.onClick();app.render();assert.equal(app.nodes().find(n=>n.props.role==='tabpanel').props['aria-labelledby'],'home-g-tab-b');assert.match(app.text(),/5.00 shares/);app.nodes().find(n=>n.props.className==='holding-open').props.onClick();assert.deepEqual(opened[0],['b','no']);
});
test('prediction tabs support keyboard switching and focus the active tab',()=>{
 const picked=[],focused=[],app=mount('OptionTabs.tsx',{id:'demo',label:'Predictions',options:[{id:'a',label:'A'},{id:'b',label:'B'}],selected:'a',select:id=>picked.push(id)});app.render();const list=app.nodes().find(n=>n.props.role==='tablist');let prevented=false;
 list.props.onKeyDown({key:'ArrowLeft',preventDefault(){prevented=true;},currentTarget:{querySelectorAll:()=>[{focus:()=>focused.push('a')},{focus:()=>focused.push('b')}]}});assert.equal(prevented,true);assert.deepEqual(picked,['b']);assert.deepEqual(focused,['b']);assert.equal(app.nodes().find(n=>n.props.role==='tab'&&n.props['aria-selected']).props.tabIndex,0);
});
test('portfolio holdings render before pending bets, and grouped listings occupy one grid column',()=>{
 const app=readFileSync(new URL('../src/App.tsx',import.meta.url),'utf8'),portfolio=app.slice(app.indexOf('function Portfolio('));assert.ok(portfolio.indexOf('<PortfolioPositions')<portfolio.indexOf('<MyOrders'));
 const css=readFileSync(new URL('../src/portfolio.css',import.meta.url),'utf8');assert.match(css,/\.group-market-card\{grid-column:auto;/);assert.doesNotMatch(readFileSync(new URL('../src/minimal.css',import.meta.url),'utf8'),/\.group-market-card\{grid-column:1\/-1/);
});

test('position cards show investment, winning payout and profit/return for each held outcome',()=>{
 const heldRows=summary.positionSummaries([market('both')],[{market_id:'both',side:'yes',shares:20},{market_id:'both',side:'no',shares:10}],{both:{yes:8,no:3}});
 const app=mount('PositionCards.tsx',{rows:heldRows,openMarket(){}});app.render();assert.match(app.text(),/Invested◈ 11/);assert.match(app.text(),/If Yes winsPayout◈ 20Profit \/ return\+◈ 9\+81.82%/);assert.match(app.text(),/If No winsPayout◈ 10Profit \/ return−◈ 1-9.09%/);assert.match(app.text(),/Only the winning side pays out/);assert.doesNotMatch(app.text(),/Current value|Profit \/ loss/);
});

test('home carousel shows three recent markets at a time, pages through all bets and keeps the full Portfolio grid',()=>{
 const markets=Array.from({length:8},(_,i)=>market(`market-${i}`)),holdings=summary.positionSummaries(markets,markets.map(m=>({market_id:m.id,side:'yes',shares:10}))),recent=Object.fromEntries(markets.map((m,i)=>[m.id,`2026-11-02T10:0${i}:00Z`]));let openedPortfolio=0;
 const app=mount('ActiveBets.tsx',{rows:holdings,recent,portfolio:()=>openedPortfolio++,openMarket(){}});app.render();const titles=()=>app.nodes().filter(n=>n.props.className==='holding-open').map(n=>n.props['aria-label']);assert.deepEqual(titles(),['Open market-7','Open market-6','Open market-5']);assert.equal(app.nodes().filter(n=>n.type==='article').length,3);assert.equal(app.field('Previous 3 bets').props.disabled,true);assert.equal(app.field('Your bets overview').props.className,'holding-strip');const frame=app.nodes().find(n=>n.props.className==='bet-carousel has-pages');assert.equal(frame.props.children[0].props['aria-label'],'Previous 3 bets');assert.equal(frame.props.children[1].props['aria-label'],'Your bets overview');assert.equal(frame.props.children[2].props['aria-label'],'Next 3 bets');
 app.field('Next 3 bets').props.onClick();app.render();assert.deepEqual(titles(),['Open market-4','Open market-3','Open market-2']);assert.match(app.text(),/2 \/ 3/);app.field('Next 3 bets').props.onClick();app.render();assert.deepEqual(titles(),['Open market-1','Open market-0']);assert.equal(app.field('Next 3 bets').props.disabled,true);app.field('Previous 3 bets').props.onClick();app.render();assert.deepEqual(titles(),['Open market-4','Open market-3','Open market-2']);
 app.nodes().find(n=>n.type==='button'&&n.props.className==='text-button').props.onClick();assert.equal(openedPortfolio,1);const portfolio=mount('PortfolioPositions.tsx',{rows:holdings,openMarket(){},error:''});portfolio.render();assert.equal(portfolio.nodes().filter(n=>n.type==='article').length,8);assert.ok(portfolio.nodes().some(n=>n.props.className==='holding-grid'));assert.equal(portfolio.field('Your bets overview'),undefined);
 app.props.rows=holdings.slice(0,1);app.render();assert.equal(app.nodes().filter(n=>n.type==='article').length,1);assert.equal(app.field('Next 3 bets'),undefined);
});
