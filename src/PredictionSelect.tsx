import {useEffect,useRef} from 'react';
import {ChevronDown} from 'lucide-react';

type Selection={options:{id:string;label:string;detail?:string}[];value:string;onChange:(id:string)=>void};

export function attachPredictionWheel(element:HTMLSelectElement,read:()=>Selection){
 let distance=0,last=-Infinity;
 const wheel=(event:WheelEvent)=>{
  const {options,value,onChange}=read();
  if(options.length<2||event.ctrlKey||event.metaKey||!event.deltaY||Math.abs(event.deltaX)>Math.abs(event.deltaY))return;
  event.preventDefault();
  if(event.timeStamp-last<160)return;
  const delta=event.deltaY*(event.deltaMode===1?16:event.deltaMode===2?100:1);
  if(Math.sign(distance)!==Math.sign(delta))distance=0;
  distance+=delta;
  if(Math.abs(distance)<30)return;
  const direction=Math.sign(distance),index=Math.max(0,options.findIndex(option=>option.id===value));
  distance=0;last=event.timeStamp;
  const next=options[Math.max(0,Math.min(options.length-1,index+direction))];
  if(next.id!==value)onChange(next.id);
 };
 element.addEventListener('wheel',wheel,{passive:false});
 return()=>element.removeEventListener('wheel',wheel);
}

export default function PredictionSelect({label,controls,...selection}:Selection&{label:string;controls?:string}){
 const element=useRef<HTMLSelectElement>(null),latest=useRef(selection);
 latest.current=selection;
 useEffect(()=>{if(element.current)return attachPredictionWheel(element.current,()=>latest.current);},[]);
 return <div className="prediction-select"><select ref={element} aria-label={label} aria-controls={controls} title={selection.options.find(option=>option.id===selection.value)?.label} value={selection.value} onChange={event=>selection.onChange(event.target.value)}>{selection.options.map(option=><option key={option.id} value={option.id}>{option.label}{option.detail?` · ${option.detail}`:''}</option>)}</select><ChevronDown size={14} aria-hidden="true"/></div>;
}
