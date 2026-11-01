import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import ts from 'typescript';import * as visuals from '../src/casino.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const compiled=ts.transpileModule(readFileSync(new URL('../src/CasinoPage.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function casino({active=null,available=1000,remaining=100,motion=true,defer=false,fail=false}={}){
 const states=[],effects=[],pending=[],calls=[],timers=new Map();let cursor=0,tree,resume,failed=false,serial=0,snapshot={active,available,remaining,recent:[]};
 const hooks={useState:init=>{const i=cursor++;if(!(i in states))states[i]=typeof init==='function'?init():init;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useRef:init=>{const i=cursor++;return states[i]??={current:init};},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i][j])){effects[i]=deps;pending.push(fn);}}};
 const supabase={rpc:async(name,args)=>{calls.push({name,args});if(name==='casino_state')return{data:snapshot};if(name==='casino_start'){
  if(defer)await new Promise(r=>resume=r);if(fail&&!failed){failed=true;return{error:{message:'Network retry'}};}
  const r={id:`round-${++serial}`,game:args.p_game,stake:args.p_stake,payout:0,version:1,status:args.p_game==='blackjack'?'active':'settled',state:args.p_game==='blackjack'?{player:[0,4],dealer:[36,null],player_total:13}:args.p_game==='roulette'?{number:3,choice:args.p_choice,outcome:'win'}:{path:[1,0,1,0,1,0,1,0],slot:4,multiplier:.4,outcome:'loss'}};
  snapshot={...snapshot,available:snapshot.available-args.p_stake,remaining:snapshot.remaining-args.p_stake,active:r.status==='active'?r:null,recent:r.status==='settled'?[r,...snapshot.recent]:snapshot.recent};return{data:r};
 }if(name==='casino_blackjack'){const r={...snapshot.active,status:'settled',version:2,payout:2*snapshot.active.stake,state:{player:[36,32],dealer:[40,24],player_total:19,dealer_total:17,outcome:'win'}};snapshot={...snapshot,active:null,recent:[r,...snapshot.recent]};return{data:r};}return{};}};
 const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./db'?{supabase}:name==='./casino.mjs'?visuals:new Proxy({},{get:()=>()=>null}),crypto:{randomUUID},setTimeout:fn=>{timers.set(fn,fn);return fn;},clearTimeout:id=>timers.delete(id)});
 const props={frozen:false,motion,tick:0,refresh(){},back(){}};
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];const text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):n.props?.['aria-hidden']?'':text(n.props?.children);
 return{calls,props,render(){cursor=0;tree=module.exports.default(props);for(const fn of pending.splice(0))fn();},button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label),text:()=>text(tree),nodes:()=>walk(tree),finish:()=>resume(),finishAnimation:()=>{for(const fn of timers.values())fn();timers.clear();}};
}
test('games only send stake/choice to server and guard duplicate starts',async()=>{
 const app=casino({defer:true});app.render();await settle();app.render();const start=app.button('Deal');start.props.onClick();start.props.onClick();const requests=app.calls.filter(c=>c.name==='casino_start');assert.equal(requests.length,1);assert.equal(requests[0].args.p_stake,1);assert.equal(requests[0].args.p_game,'blackjack');assert.equal('payout' in requests[0].args,false);assert.equal('deck' in requests[0].args,false);app.finish();await settle();app.render();assert.ok(app.button('Hit'));assert.equal(app.field('Game stake'),undefined);
});
test('blackjack resumes an active hand and sends the expected action version',async()=>{
 const active={id:'existing',game:'blackjack',stake:2,status:'active',version:3,state:{player:[0,4],dealer:[36,null],player_total:13}};const app=casino({active});app.render();await settle();app.render();assert.ok(app.button('Stand'));assert.match(app.text(),/Stake ◈ 2/);await app.button('Stand').props.onClick();await settle();app.render();const action=app.calls.find(c=>c.name==='casino_blackjack');assert.equal(action.args.p_version,3);assert.equal(action.args.p_round,'existing');assert.match(app.text(),/You won/);assert.ok(app.button('Deal'));
});
test('roulette and plinko are playable with animations disabled',async()=>{
 const app=casino({motion:false});app.render();await settle();app.render();app.button('Roulette').props.onClick();app.render();app.button('Black').props.onClick();app.render();await app.button('Spin').props.onClick();await settle();app.render();assert.equal(app.calls.find(c=>c.name==='casino_start').args.p_choice,'black');assert.ok(app.nodes().some(n=>n.props['aria-label']==='Roulette result 3'));
 app.button('Plinko').props.onClick();app.render();await app.button('Drop').props.onClick();await settle();app.render();assert.equal(app.nodes().some(n=>n.type==='animateMotion'),false);app.props.motion=true;app.render();assert.equal(app.nodes().some(n=>n.type==='animateMotion'),false);assert.equal(app.button('Drop').props.disabled,false);
});
test('invalid stakes, timeouts and exhausted owned-credit/daily budgets cannot start games',async()=>{
 for(const opts of [{available:0},{remaining:0}]){const app=casino(opts);app.render();await settle();app.render();assert.equal(app.button('Deal').props.disabled,true);await app.button('Deal').props.onClick();assert.equal(app.calls.some(c=>c.name==='casino_start'),false);}
 const app=casino();app.render();await settle();app.render();app.field('Game stake').props.onChange({target:{value:'6'}});app.render();assert.equal(app.button('Deal').props.disabled,true);app.props.frozen=true;app.render();assert.equal(app.button('Account timed out').props.disabled,true);
});
test('an uncertain request keeps its nonce for retry rather than drawing a new result',async()=>{
 const app=casino({fail:true});app.render();await settle();app.render();await app.button('Deal').props.onClick();await settle();app.render();assert.match(app.text(),/Network retry/);await app.button('Deal').props.onClick();await settle();const starts=app.calls.filter(c=>c.name==='casino_start');assert.equal(starts.length,2);assert.equal(starts[0].args.p_request,starts[1].args.p_request);
});
test('wheel, cards and plinko visuals map exactly to server outcomes',()=>{
 assert.equal(new Set(visuals.wheel).size,37);assert.equal(visuals.redNumbers.size,18);for(const n of visuals.wheel){assert.ok(visuals.wheelRotation(n)>=1800);assert.ok(visuals.wheelWedge(n).startsWith('M150 150'));}assert.deepEqual(visuals.cardFace(0),{rank:'A',suit:'♠',red:false});assert.equal(visuals.cardFace(51).rank,'K');assert.throws(()=>visuals.cardFace(52));
 assert.equal(visuals.plinkoPath(Array(8).fill(0)).x,30);assert.equal(visuals.plinkoPath(Array(8).fill(1)).x,270);assert.throws(()=>visuals.plinkoPath([2]));const weights=[1,8,28,56,70,56,28,8,1];assert.ok(Math.abs(visuals.multipliers.reduce((sum,m,i)=>sum+m*weights[i]/256,0)-.99375)<1e-9);
});

test('plinko waits for the visible drop before revealing the result and prevents overlapping rounds',async()=>{
 const app=casino();app.render();await settle();app.render();app.button('Plinko').props.onClick();app.render();app.button('Drop').props.onClick();await settle();app.render();
 assert.match(app.text(),/Dropping…/);assert.doesNotMatch(app.text(),/Round over|loss · Stake/);assert.equal(app.button('Dropping…').props.disabled,true);
 app.button('Dropping…').props.onClick();await settle();assert.equal(app.calls.filter(c=>c.name==='casino_start').length,1);
 app.button('Blackjack').props.onClick();app.render();assert.ok(app.button('Dropping…'));
 app.finishAnimation();app.render();assert.match(app.text(),/Round over/);assert.ok(app.button('Drop'));assert.equal(app.button('Drop').props.disabled,false);
 app.button('Drop').props.onClick();await settle();app.render();assert.match(app.text(),/Dropping…/);app.props.motion=false;app.render();assert.match(app.text(),/Round over/);assert.equal(app.button('Drop').props.disabled,false);
});
test('plinko motion follows every selected pin and lands exactly in its server slot',()=>{
 for(let outcome=0;outcome<256;outcome++){const bits=Array.from({length:8},(_,i)=>(outcome>>i)&1);assert.deepEqual(visuals.plinkoPoint(bits,0),{x:150,y:12});assert.deepEqual(visuals.plinkoPoint(bits,1),{x:visuals.plinkoPath(bits).x,y:270});for(let step=0;step<=90;step++){const point=visuals.plinkoPoint(bits,step/90);assert.ok(point.x>=30&&point.x<=270);assert.ok(point.y>=0&&point.y<=270);}}
 assert.equal(visuals.plinkoDuration,2800);
});
