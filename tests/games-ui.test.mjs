import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync}from'node:fs';import ts from'typescript';import * as snake from'../src/snake.mjs';import {randomUUID}from'node:crypto';
const settle=()=>new Promise(r=>setImmediate(r));
function renderFile(file,{seed=[],rpc=async()=>({data:{casino_daily_limit:100}}),props={}}={}){const states=[...seed],effects=[],pending=[],calls=[],cleanups=[],listeners=new Map();let cursor=0,tree;const hooks={useState:init=>{const i=cursor++;if(!(i in states))states[i]=typeof init==='function'?init():init;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useRef:init=>{const i=cursor++;return states[i]??={current:init};},useEffect:(fn,deps)=>{const i=cursor++;if(!effects[i]||deps.some((d,j)=>d!==effects[i][j])){effects[i]=deps;pending.push(()=>{cleanups[i]?.();cleanups[i]=fn();});}}};const jsx=(type,props)=>({type,props:props??{}}),module={exports:{}};vm.runInNewContext(ts.transpileModule(readFileSync(new URL('../src/'+file,import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX}}).outputText,{exports:module.exports,require:name=>name==='react'?hooks:name==='react/jsx-runtime'?{jsx,jsxs:jsx}:name==='./snake.mjs'?snake:name==='./db'?{supabase:{rpc:(name,args)=>{calls.push({name,args});return rpc(name,args);}}}:new Proxy({},{get:()=>()=>null}),crypto:{randomUUID},Promise,window:{addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:name=>listeners.delete(name)},setInterval:()=>1,clearInterval(){},document:{hidden:false}});const nodes=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(nodes):[n,...nodes(n.props?.children)],text=n=>n==null||typeof n==='boolean'?'':typeof n!=='object'?String(n):Array.isArray(n)?n.map(text).join(''):text(n.props?.children);return{props,calls,key(event){listeners.get('keydown')?.(event);},unmount(){for(const cleanup of cleanups)cleanup?.();},render(){cursor=0;tree=module.exports.default(props);for(const fn of pending.splice(0))fn();},node:fn=>nodes(tree).find(fn),button:name=>nodes(tree).find(n=>n.type==='button'&&text(n)===name),text:()=>text(tree)};}
test('Snake game-over offers Play again even before the final running state has cleared',()=>{
 const app=renderFile('SnakeGame.tsx',{seed:[{session:{id:'fixture',state:{...snake.snakeInitial(),over:true,score:3},status:'over',awarded:3},earned:3},true,false,''],props:{frozen:false,motion:true,refresh(){}}});app.render();assert.ok(app.button('Play again'));assert.equal(app.button('Pause'),undefined);assert.match(app.text(),/Game over/);
});
test('admin casino setting loads, keeps a typed draft across live refresh, and saves the selected daily budget',async()=>{
 let saved=100;const app=renderFile('AdminGameSettings.tsx',{props:{tick:0,refresh(){},notify(){}},rpc:async(name,args)=>{if(name==='admin_game_settings')saved=args.p_daily_limit;return{data:{casino_daily_limit:saved}};}});app.render();await settle();app.render();const field=app.node(n=>n.props['aria-label']==='Daily casino limit');field.props.onChange({target:{value:'250'}});app.render();app.props.tick++;app.render();await settle();app.render();assert.equal(app.node(n=>n.props['aria-label']==='Daily casino limit').props.value,'250');app.node(n=>n.type==='form').props.onSubmit({preventDefault(){}});await settle();app.render();assert.equal(saved,250);assert.equal(app.calls.filter(c=>c.name==='admin_game_settings').length,1);assert.ok(app.button('Save limit'));
});


test('Snake starts and restarts with Enter or Space, ignores repeats and keeps native controls intact',async()=>{
 for(const key of ['Enter',' '])for(const over of [false,true]){
  let snapshot={session:over?{id:'previous',state:{...snake.snakeInitial(),over:true},status:'over'}:null,earned:0};
  const app=renderFile('SnakeGame.tsx',{props:{frozen:false,motion:false,refresh(){}},rpc:async name=>{
   if(name==='snake_start')snapshot={session:{id:'new',state:snake.snakeInitial(),status:'active'},earned:0};return{data:snapshot};
  }});
  app.render();await settle();app.render();let prevented=0;
  const event={key,code:key===' '?'Space':'Enter',target:{closest:()=>null},preventDefault(){prevented++;}};
  app.key({...event,repeat:true});assert.equal(app.calls.filter(c=>c.name==='snake_start').length,0);
  app.key({...event,target:{closest:()=>({})}});assert.equal(app.calls.filter(c=>c.name==='snake_start').length,0);
  app.key(event);app.key(event);await settle();app.render();assert.equal(app.calls.filter(c=>c.name==='snake_start').length,1);assert.ok(app.button('Pause'));assert.ok(prevented>0);
  const board=app.node(n=>n.props.className?.startsWith('snake-board'));board.props.ref.current=event.target;app.key({...event,key:' ',code:'Space'});app.render();assert.ok(app.button('Resume'));
  app.props.active=false;app.render();app.key(event);assert.equal(app.calls.filter(c=>c.name==='snake_start').length,1);
  app.unmount();app.key(event);assert.equal(app.calls.filter(c=>c.name==='snake_start').length,1);
 }
});
test('Snake keyboard start respects loading, timeouts and save errors',async()=>{
 for(const mode of ['loading','frozen','error']){
  const app=renderFile('SnakeGame.tsx',{props:{frozen:mode==='frozen',motion:false,refresh(){}},rpc:async()=>mode==='loading'?new Promise(()=>{}):mode==='error'?{error:{message:'Save failed'}}:{data:{session:null,earned:0}}});
  app.render();await settle();app.render();let prevented=false;app.key({key:'Enter',target:{closest:()=>null},preventDefault(){prevented=true;}});assert.equal(app.calls.filter(c=>c.name==='snake_start').length,0);assert.equal(prevented,false);app.unmount();
 }
});
