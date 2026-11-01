import {useEffect,useRef} from 'react';
import {snakeFrame} from './snake-art.mjs';
import {snakeTick} from './snake.mjs';
export default function SnakeArtwork({body,direction,chip,motion}:{body:number[];direction:number;chip:number;motion:boolean}){
 const line=useRef<SVGPathElement>(null),face=useRef<SVGGElement>(null),previous=useRef(body),initial=useRef(snakeFrame(body,body,1)),pattern=body.join(',');
 useEffect(()=>{
  const from=previous.current;previous.current=body;let frame=0;const start=performance.now();
  const paint=(progress:number)=>{const drawing=snakeFrame(from,body,progress);line.current?.setAttribute('d',drawing.d);face.current?.setAttribute('transform',`translate(${drawing.head.x} ${drawing.head.y})`);};
  if(!motion){paint(1);return;}
  paint(0);
  const step=(time:number)=>{const progress=Math.min(1,(time-start)/snakeTick);paint(progress);if(progress<1)frame=requestAnimationFrame(step);};
  frame=requestAnimationFrame(step);return()=>cancelAnimationFrame(frame);
 },[pattern,motion]);
 return <svg viewBox="0 0 400 400" aria-hidden="true">{chip>=0&&<g className="snake-chip" transform={`translate(${chip%20*20+10} ${Math.floor(chip/20)*20+10})`}><path d="M0 -8L8 0 0 8 -8 0Z" fill="none" stroke="white" strokeWidth="1.5"/><path d="M0 -4L4 0 0 4 -4 0Z" fill="white"/></g>}<path ref={line} className="snake-body" d={initial.current.d} fill="none" stroke="white" strokeWidth="18" strokeLinecap="round" strokeLinejoin="round"/><g ref={face} transform={`translate(${initial.current.head.x} ${initial.current.head.y})`}><g className="snake-eyes" transform={`rotate(${direction*90})`}><circle cx="-4" cy="-4" r="1.6"/><circle cx="4" cy="-4" r="1.6"/></g></g></svg>;
}
