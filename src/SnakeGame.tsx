import {useEffect,useRef,useState} from 'react';
import {ArrowUp,ArrowDown,ArrowLeft,ArrowRight,Pause,Play,RotateCcw} from 'lucide-react';
import {supabase} from './db';
import SnakeArtwork from './SnakeArtwork';
import {SnakeTransport,snakeInitial,snakeTick} from './snake.mjs';
import type {SnakeSnapshot} from './snake.mjs';
const keys:Record<string,number>={ArrowUp:0,w:0,W:0,ArrowRight:1,d:1,D:1,ArrowDown:2,s:2,S:2,ArrowLeft:3,a:3,A:3};
export default function SnakeGame({frozen,motion,refresh,active=true}:{frozen:boolean;motion:boolean;active?:boolean;refresh:()=>void}){
 const[snapshot,setSnapshot]=useState<SnakeSnapshot|null>(null),[running,setRunning]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const transport=useRef<SnakeTransport|null>(null),board=useRef<HTMLDivElement>(null),turns=useRef<number[]>([]),swipe=useRef<{x:number;y:number}|null>(null),refreshRef=useRef(refresh),flight=useRef(false),visible=useRef(active),shortcut=useRef<(event:KeyboardEvent)=>void>(()=>{});
 refreshRef.current=refresh;visible.current=active;
 useEffect(()=>{let mounted=true;const client=new SnakeTransport((name,args)=>supabase.rpc(name,args),data=>{if(mounted)setSnapshot(data);},message=>{if(mounted){setError(message);setRunning(false);}},()=>refreshRef.current());transport.current=client;void client.load().catch(e=>{if(mounted)setError(e.message||'Could not load Snake.');});return()=>{mounted=false;client.dispose();};},[]);
 const state=snapshot?.session?.state??snakeInitial(),over=state.over||snapshot?.session?.status==='over';
 const turn=(direction:number)=>{const client=transport.current;if(!client||turns.current.length>=2)return;const previous=turns.current.at(-1)??client.state.direction;if(direction!==previous&&(direction+2)%4!==previous)turns.current.push(direction);};
 const pause=()=>{setRunning(false);void transport.current?.flush();};
 useEffect(()=>{if(!active||!running||frozen||error||over)return;const timer=setInterval(()=>{if(document.hidden){setRunning(false);void transport.current?.flush();return;}const client=transport.current;if(!client)return;const next=turns.current[0]??client.state.direction;if(client.move(next)&&turns.current.length)turns.current.shift();},snakeTick);return()=>clearInterval(timer);},[active,running,frozen,error,over]);
 useEffect(()=>{if(frozen||!active)pause();},[frozen,active]);
 const start=async(restart=false)=>{if(flight.current||frozen||!active)return;flight.current=true;setBusy(true);setError('');try{if(restart||!snapshot?.session||over){if(!await transport.current?.start(restart))return;}if(!visible.current)return;turns.current=[];setRunning(true);board.current?.focus({preventScroll:true});}catch(e){setError((e as Error).message||'Could not start Snake.');}finally{flight.current=false;setBusy(false);}};
 shortcut.current=event=>{
  if(event.defaultPrevented||event.repeat||event.isComposing||event.ctrlKey||event.metaKey||event.altKey||!active||frozen||busy||error||!snapshot)return;
  const space=event.code==='Space'||event.key===' ';
  if(event.key!=='Enter'&&!space)return;
  const target=event.target as HTMLElement|null;
  if(target?.closest?.('button,input,textarea,select,a,[contenteditable]'))return;
  if(running&&!over){if(space&&target===board.current){event.preventDefault();pause();}return;}
  event.preventDefault();void start();
 };
 useEffect(()=>{const keydown=(event:KeyboardEvent)=>shortcut.current(event);window.addEventListener('keydown',keydown);return()=>window.removeEventListener('keydown',keydown);},[]);
 return <section className="snake-game" onKeyDown={e=>{const direction=keys[e.key];if(direction!==undefined){e.preventDefault();turn(direction);}}}>
  <div className="snake-heading"><h2>Snake</h2><span aria-live="polite">Today ◈ {snapshot?.earned??0} / 100</span></div>
  <div className="snake-layout"><div ref={board} tabIndex={0} className={`snake-board ${motion?'snake-motion':''}`} role="group" aria-label="Snake board. Enter or Space to start or play again; arrow keys or WASD to move; Space to pause." onPointerDown={e=>{swipe.current={x:e.clientX,y:e.clientY};e.currentTarget.setPointerCapture(e.pointerId);}} onPointerUp={e=>{const from=swipe.current;swipe.current=null;if(!from)return;const x=e.clientX-from.x,y=e.clientY-from.y;if(Math.max(Math.abs(x),Math.abs(y))<12)return;turn(Math.abs(x)>Math.abs(y)?x>0?1:3:y>0?2:0);}} onPointerCancel={()=>{swipe.current=null;}}>
   <SnakeArtwork body={state.body} direction={state.direction} chip={state.apple} motion={motion&&running&&active&&!over}/>
   {(!running||over||frozen)&&<div className="snake-overlay"><strong>{frozen?'Account timed out':over?'Game over':snapshot?.session?'Paused':'Snake'}</strong><span>{over?`${state.score} ${state.score===1?'chip':'chips'}`:'1 diamond = 1 chip'}</span></div>}
  </div><aside className="settings-card snake-controls"><div className="snake-score"><span>Collected</span><strong>{state.score}</strong></div><p>1 chip per diamond · up to 100 per day. Keep playing after the cap.</p><div className="game-actions"><button className="primary" disabled={busy||frozen||!snapshot||!!error} onClick={()=>running&&!over?pause():void start()}>{running&&!over?<><Pause size={15}/>Pause</>:<><Play size={15}/>{over?'Play again':snapshot?.session?'Resume':'Play'}</>}</button>{snapshot?.session&&!running&&!over&&<button className="secondary" disabled={busy||frozen||!!error} onClick={()=>void start(true)}><RotateCcw size={15}/>Restart</button>}</div>
   <div className="snake-dpad" aria-label="Snake direction controls">{[{name:'Up',dir:0,Icon:ArrowUp},{name:'Left',dir:3,Icon:ArrowLeft},{name:'Down',dir:2,Icon:ArrowDown},{name:'Right',dir:1,Icon:ArrowRight}].map(({name,dir,Icon})=><button key={name} className={`snake-${name.toLowerCase()}`} aria-label={`Move ${name.toLowerCase()}`} disabled={!running||over||frozen} onClick={()=>turn(dir)}><Icon size={22}/></button>)}</div><small>Enter / Space to play or restart · Space to pause · Arrows / WASD · swipe</small>
   {error&&<div className="snake-error"><p className="form-error" role="alert">{error}</p><div className="game-actions"><button className="secondary" disabled={busy||frozen} onClick={()=>{if(flight.current)return;flight.current=true;setBusy(true);void transport.current?.retry().then(()=>{if(!transport.current?.error)setError('');}).finally(()=>{flight.current=false;setBusy(false);});}}>Retry save</button><button className="text-button" disabled={busy} onClick={()=>{if(flight.current)return;flight.current=true;setBusy(true);void transport.current?.load().then(()=>{setError('');turns.current=[];}).catch(e=>setError(e.message)).finally(()=>{flight.current=false;setBusy(false);});}}>Reload game</button></div></div>}
  </aside></div>
 </section>;
}
