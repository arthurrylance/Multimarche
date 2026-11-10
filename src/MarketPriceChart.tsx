import {useState} from 'react';
import type {PointerEvent} from 'react';
import {formatDateTime} from './display-format.mjs';

const format=(value:number,digits:number)=>value.toLocaleString('en-US',{maximumFractionDigits:digits});
const ranges=['1H','1D','1W','ALL'];
type PricePoint={created_at:string;probability:number};

export default function MarketPriceChart({history,range,setRange}:{history:PricePoint[];range:string;setRange:(range:string)=>void}){
 const [cursor,setCursor]=useState<number|null>(null);
 const points=history.map(point=>({...point,time:Date.parse(point.created_at),price:Number(point.probability)}))
  .filter(point=>point.probability!=null&&Number.isFinite(point.time)&&Number.isFinite(point.price)&&point.price>=0&&point.price<=1)
  .sort((a,b)=>a.time-b.time);
 const first=points[0]?.time??0,last=points.at(-1)?.time??first;
 const x=(index:number)=>30+(last===first?index/Math.max(1,points.length-1):(points[index].time-first)/(last-first))*660;
 const y=(index:number)=>190-points[index].price*160;
 const selected=cursor===null?null:Math.min(cursor,points.length-1);
 const point=selected===null?null:points[selected];
 const describe=(value:typeof points[number])=>`${formatDateTime(value.time)} · ${format(value.price*100,2)}% · ◈ ${format(value.price,4)} per Yes share`;
 const scrub=(event:PointerEvent<SVGSVGElement>)=>{
  const rect=event.currentTarget.getBoundingClientRect();
  if(!rect.width||!points.length)return;
  const position=(event.clientX-rect.left)/rect.width*720;
  let low=0,high=points.length-1;
  while(low<high){const middle=Math.floor((low+high)/2);if(position>(x(middle)+x(middle+1))/2)low=middle+1;else high=middle;}
  setCursor(low);
 };
 return <div className="price-chart"><div className="chart-axis"><span>100%</span><span>50%</span><span>0%</span></div>
  {points.length>0&&<div className="chart-readout" aria-hidden="true">{point?describe(point):'Hover or scrub to see historical prices'}</div>}
  <svg viewBox="0 0 720 220" preserveAspectRatio="none" tabIndex={points.length?0:undefined} role={points.length?'slider':'img'} aria-label="Historical Yes price" aria-valuemin={points.length?1:undefined} aria-valuemax={points.length||undefined} aria-valuenow={points.length?(selected??points.length-1)+1:undefined} aria-valuetext={points.length?describe(point??points[points.length-1]):undefined}
   onPointerMove={scrub} onPointerDown={event=>{if(event.pointerType==='touch')event.currentTarget.setPointerCapture(event.pointerId);scrub(event);}} onPointerLeave={event=>{if(event.pointerType!=='touch')setCursor(null);}}
   onFocus={()=>setCursor(previous=>previous??(points.length?points.length-1:null))} onBlur={()=>setCursor(null)} onKeyDown={event=>{
    if(!points.length||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))return;
    event.preventDefault();const index=selected??points.length-1;
    const next=event.key==='Home'?0:event.key==='End'?points.length-1:index+(['ArrowLeft','ArrowDown'].includes(event.key)?-1:1);
    setCursor(Math.max(0,Math.min(points.length-1,next)));
   }}>
   <path d="M30 30H690M30 110H690M30 190H690" stroke="#edf0f4" strokeDasharray="4 5"/>
   <polyline points={points.map((_,index)=>`${x(index)},${y(index)}`).join(' ')} fill="none" stroke="#2563eb" strokeWidth="2.5"/>
   {points.length===1&&<circle cx={x(0)} cy={y(0)} r="4"/>}
   {point&&selected!==null&&<g className="chart-cursor" aria-hidden="true"><line x1={x(selected)} x2={x(selected)} y1="30" y2="190"/><circle cx={x(selected)} cy={y(selected)} r="5"/></g>}
  </svg>
  <div className="chart-foot"><span>{!points.length?'No price history in this period':points.length===1?'One recorded price':'Yes share price · recorded history'}</span><div>{ranges.map(value=><button key={value} className={value===range?'active':''} aria-pressed={value===range} onClick={()=>setRange(value)}>{value}</button>)}</div></div>
 </div>;
}
