import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {randomUUID} from 'node:crypto';import ts from 'typescript';import * as visuals from '../src/casino.mjs';
const settle=()=>new Promise(resolve=>setImmediate(resolve));
const compiled=ts.transpileModule(readFileSync(new URL('../src/CasinoPage.tsx',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function casino({active=null,available=1000,remaining=100,motion=true,defer=false,fail=false,rouletteNumber=3}={}){
 const states=[],effects=[],cleanups=[],pending=[],calls=[],timers=new Map();let cursor=0,tree,resume,failed=false,serial=0,snapshot={active,available,remaining,recent:[]};
 const hooks={useState:init=>{const i=cursor++;if(!(i in states))states[i]=typeof init==='function'?init():init;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useRef:init=>{const i=cursor++;return states[i]??={current:init};},useCallback:(fn,deps)=>{const i=cursor++;if(!states[i]||deps.some((v,j)=>v!==states[i].deps[j]))states[i]={fn,deps};return states[i].fn;},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((v,j)=>v!==effects[i][j])){effects[i]=deps;pending.push(()=>{cleanups[i]?.();cleanups[i]=fn();});}}};
 const supabase={rpc:async(name,args)=>{calls.push({name,args});if(name==='casino_state')return{data:snapshot};if(name==='casino_plinko_batch'){const results=Array.from({length:args.p_count},()=>({id:`round-${++serial}`,game:'plinko',stake:args.p_stake,payout:args.p_stake*.4,version:1,status:'settled',state:{path:[1,0,1,0,1,0,1,0],slot:4,multiplier:.4,outcome:'loss'}}));snapshot={...snapshot,available:snapshot.available-args.p_stake*args.p_count,remaining:snapshot.remaining-args.p_stake*args.p_count,recent:[...results,...snapshot.recent]};return{data:results};}if(name==='casino_start'){
  if(defer)await new Promise(r=>resume=r);if(fail&&!failed){failed=true;return{error:{message:'Network retry'}};}
  const r={id:`round-${++serial}`,game:args.p_game,stake:args.p_stake,payout:0,version:1,status:args.p_game==='blackjack'?'active':'settled',state:args.p_game==='blackjack'?{player:[0,4],dealer:[36,null],player_total:13}:args.p_game==='roulette'?{number:rouletteNumber,choice:args.p_choice,outcome:'win'}:{path:[1,0,1,0,1,0,1,0],slot:4,multiplier:.4,outcome:'loss'}};
  if(r.game==='roulette'){const n=r.state.number,won=n!==0&&(args.p_choice==='red'?visuals.redNumbers.has(n):args.p_choice==='black'?!visuals.redNumbers.has(n):args.p_choice==='odd'?n%2===1:n%2===0);r.state.outcome=won?'win':'loss';r.payout=won?2*args.p_stake:0;}
  snapshot={...snapshot,available:snapshot.available-args.p_stake+r.payout,remaining:snapshot.remaining-args.p_stake,active:r.status==='active'?r:null,recent:r.status==='settled'?[r,...snapshot.recent]:snapshot.recent};return{data:r};
 }if(name==='casino_blackjack'){const r={...snapshot.active,status:'settled',version:2,payout:2*snapshot.active.stake,state:{player:[36,32],dealer:[40,24],player_total:19,dealer_total:17,outcome:'win'}};snapshot={...snapshot,active:null,recent:[r,...snapshot.recent]};return{data:r};}return{};}};
 const SnakeStub=()=>null;const jsx=(type,props,key)=>({type,props:props??{},key}),module={exports:{}};vm.runInNewContext(compiled,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./db'?{supabase}:name==='./casino.mjs'?visuals:name==='./SnakeGame'?{__esModule:true,default:SnakeStub}:new Proxy({},{get:()=>()=>null}),crypto:{randomUUID},setTimeout:(fn,delay)=>{timers.set(fn,{fn,delay});return fn;},clearTimeout:id=>timers.delete(id)});
 const props={frozen:false,motion,tick:0,refresh(){},back(){}};
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];const text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):n.props?.['aria-hidden']?'':text(n.props?.children);
 return{calls,props,render(){cursor=0;tree=module.exports.default(props);for(const fn of pending.splice(0))fn();},button:label=>walk(tree).find(n=>n.type==='button'&&text(n)===label),field:label=>walk(tree).find(n=>n.props['aria-label']===label),text:()=>text(tree),nodes:()=>walk(tree),finish:()=>resume(),timers:()=>[...timers.values()],finishAnimation:()=>{for(const [id,{fn}] of [...timers]){timers.delete(id);fn();}}};
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

test('plinko batches and overlapping drops retain independent animations and respect total stake',async()=>{
 const app=casino();app.render();await settle();app.render();app.button('Plinko').props.onClick();app.render();app.field('Plinko balls').props.onChange({target:{value:'3'}});app.render();app.button('Drop').props.onClick();await settle();app.render();
 assert.match(app.text(),/3 balls falling/);assert.doesNotMatch(app.text(),/Round over|loss · Stake/);assert.equal(app.button('Drop').props.disabled,false);assert.equal(app.nodes().filter(n=>n.type?.name==='PlinkoBall'&&n.props.animate).length,3);
 app.button('Drop').props.onClick();await settle();app.render();assert.match(app.text(),/6 balls falling/);assert.equal(app.calls.filter(c=>c.name==='casino_plinko_batch').length,2);assert.equal(app.nodes().filter(n=>n.type?.name==='PlinkoBall'&&n.props.animate).length,6);
 app.button('Blackjack').props.onClick();app.render();assert.ok(app.field('Plinko balls'));
 app.props.motion=false;app.render();assert.match(app.text(),/Round over/);assert.equal(app.button('Drop').props.disabled,false);
 const poor=casino({available:2});poor.render();await settle();poor.render();poor.button('Plinko').props.onClick();poor.render();poor.field('Plinko balls').props.onChange({target:{value:'3'}});poor.render();assert.equal(poor.button('Drop').props.disabled,true);poor.button('Drop').props.onClick();await settle();assert.equal(poor.calls.some(c=>c.name==='casino_plinko_batch'),false);
});
test('plinko motion follows every selected pin and lands exactly in its server slot',()=>{
 for(let outcome=0;outcome<256;outcome++){const bits=Array.from({length:8},(_,i)=>(outcome>>i)&1);assert.deepEqual(visuals.plinkoPoint(bits,0),{x:150,y:12});assert.deepEqual(visuals.plinkoPoint(bits,1),{x:visuals.plinkoPath(bits).x,y:270});for(let step=0;step<=90;step++){const point=visuals.plinkoPoint(bits,step/90);assert.ok(point.x>=30&&point.x<=270);assert.ok(point.y>=0&&point.y<=270);}}
 assert.equal(visuals.plinkoDuration,2800);
});

test('game section tabs preserve the mounted Snake instance and keep the shared wallet heading stable',async()=>{
 const app=casino();app.render();await settle();app.render();const snakeNode=app.nodes().find(n=>n.props.active===false&&'refresh' in n.props);assert.ok(snakeNode);assert.match(app.text(),/Available credits/);const casinoPanel=()=>app.nodes().find(n=>n.props.id==='casino-games');assert.equal(casinoPanel().props.inert,false);
 app.button('General games').props.onClick();app.render();assert.ok(app.nodes().some(n=>n.type===snakeNode.type&&n.props.active===true));assert.equal(casinoPanel().props.inert,true);app.button('Casino').props.onClick();app.render();assert.ok(app.nodes().some(n=>n.type===snakeNode.type&&n.props.active===false));assert.match(app.text(),/Available credits/);
});
test('Plinko accepts larger whole-credit per-ball amounts but guards the total daily budget',async()=>{
 const app=casino();app.render();await settle();app.render();app.button('Plinko').props.onClick();app.render();app.field('Plinko balls').props.onChange({target:{value:'3'}});app.field('Game stake').props.onChange({target:{value:'25'}});app.render();assert.equal(app.button('Drop').props.disabled,false);app.button('Drop').props.onClick();await settle();app.render();const call=app.calls.find(c=>c.name==='casino_plinko_batch');assert.equal(call.args.p_stake,25);assert.equal(call.args.p_count,3);assert.equal(app.button('Drop').props.disabled,true);
});
test('each landing retriggers only its multiplier flash, including repeated hits in one slot',async()=>{
 const app=casino();app.render();await settle();app.render();app.button('Plinko').props.onClick();app.render();app.field('Plinko balls').props.onChange({target:{value:'3'}});app.render();app.button('Drop').props.onClick();await settle();app.render();const balls=app.nodes().filter(n=>n.type?.name==='PlinkoBall'&&n.props.animate);balls[0].props.onLand();app.render();let hit=app.nodes().find(n=>n.type==='span'&&n.props.className?.includes('bin-hit'));assert.ok(hit);const key=hit.key;balls[1].props.onLand();app.render();hit=app.nodes().find(n=>n.type==='span'&&n.props.className?.includes('bin-hit'));assert.notEqual(hit.key,key);assert.equal(app.nodes().filter(n=>n.type==='span'&&n.props.className?.includes('bin-hit')).length,1);
});

const startRoulette=async(options)=>{const app=casino(options);app.render();await settle();app.render();app.button('Roulette').props.onClick();app.render();await app.button('Spin').props.onClick();await settle();app.render();return app;};
const wheelNode=app=>app.nodes().find(n=>n.type==='svg'&&n.props.className?.includes('roulette-wheel'));
const endWheel=(app,name='mm-wheel')=>{const wheel=wheelNode(app),element={};wheel.props.onAnimationEnd({target:element,currentTarget:element,animationName:name});app.render();};
const outcome=app=>app.nodes().find(n=>n.props.className?.startsWith('game-outcome'));
const nodeText=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(nodeText).join(''):nodeText(n.props?.children);
test('roulette hides the outcome, number, balance and history until its wheel finishes',async()=>{
 const app=await startRoulette();assert.equal(nodeText(outcome(app)),'Spinning…');assert.doesNotMatch(app.text(),/You won|win · Stake/);
 assert.equal(wheelNode(app).props['aria-label'],'Roulette wheel spinning');assert.equal(nodeText(app.nodes().find(n=>n.props.className==='roulette-result ')),'…');assert.match(app.text(),/◈ …/);
 assert.equal(app.button('Spinning…').props.disabled,true);assert.equal(app.button('Plinko').props.disabled,true);
 const starts=app.calls.filter(c=>c.name==='casino_start').length;app.button('Spinning…').props.onClick();await settle();assert.equal(app.calls.filter(c=>c.name==='casino_start').length,starts);
 app.props.tick++;app.render();await settle();app.render();assert.doesNotMatch(app.text(),/You won|win · Stake/);
 endWheel(app,'mm-reveal');assert.equal(nodeText(outcome(app)),'Spinning…');
 endWheel(app);assert.match(nodeText(outcome(app)),/You won/);assert.equal(wheelNode(app).props['aria-label'],'Roulette result 3');assert.match(app.text(),/win · Stake/);assert.equal(app.button('Spin').props.disabled,false);assert.equal(app.timers().length,0);
});
test('roulette losses and zero are also hidden until animation completion',async()=>{
 for(const number of [0,2]){const app=await startRoulette({rouletteNumber:number});assert.equal(nodeText(outcome(app)),'Spinning…');assert.doesNotMatch(app.text(),/Round over|loss · Stake/);endWheel(app);assert.match(nodeText(outcome(app)),/Round over/);assert.equal(wheelNode(app).props['aria-label'],`Roulette result ${number}`);}
});
test('missing wheel events use a duration-matched fallback; stale events cannot reveal the next spin',async()=>{
 const app=await startRoulette(),old=wheelNode(app);assert.equal(app.timers().length,1);assert.ok(app.timers()[0].delay>visuals.rouletteDuration);assert.equal(old.props.style['--roulette-duration'],`${visuals.rouletteDuration}ms`);
 app.finishAnimation();app.render();assert.match(nodeText(outcome(app)),/You won/);
 await app.button('Spin').props.onClick();await settle();app.render();const element={};old.props.onAnimationEnd({target:element,currentTarget:element,animationName:'mm-wheel'});app.render();assert.equal(nodeText(outcome(app)),'Spinning…');endWheel(app);assert.match(nodeText(outcome(app)),/You won/);
});
test('disabling motion reveals immediately and restoring motion does not replay a completed wheel',async()=>{
 const app=await startRoulette();app.props.motion=false;app.render();app.render();assert.match(nodeText(outcome(app)),/You won/);assert.equal(app.button('Spin').props.disabled,false);assert.equal(app.timers().length,0);
 app.props.motion=true;app.render();assert.equal(wheelNode(app).props.className.includes('has-result'),false);assert.match(nodeText(outcome(app)),/You won/);
 const immediate=await startRoulette({motion:false});assert.match(nodeText(outcome(immediate)),/You won/);assert.equal(immediate.timers().length,0);assert.equal(wheelNode(immediate).props.className.includes('has-result'),false);
});
