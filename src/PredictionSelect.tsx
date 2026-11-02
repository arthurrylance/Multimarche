import {ChevronRight} from 'lucide-react';

type Selection={options:{id:string;label:string;detail?:string}[];value:string;onChange:(id:string)=>void};

export default function PredictionSelect({label,controls,options,value,onChange}:Selection&{label:string;controls?:string}){
 const index=Math.max(0,options.findIndex(option=>option.id===value)),selected=options[index];
 if(!selected)return null;
 const choose=(next:number)=>{const option=options[(next+options.length)%options.length];if(options.length>1&&option.id!==value)onChange(option.id);};
 return <div className="prediction-select"><button type="button" aria-label={`${label}: ${selected.label}. Next option`} aria-controls={controls} title={`${selected.label} · Click for next option`} disabled={options.length<2} onClick={()=>choose(index+1)} onKeyDown={event=>{if(event.altKey||event.ctrlKey||event.metaKey)return;if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;event.preventDefault();choose(event.key==='Home'?0:event.key==='End'?options.length-1:index+(event.key==='ArrowLeft'?-1:1));}}><span aria-live="polite">{selected.label}{selected.detail?` · ${selected.detail}`:''}</span><small aria-label={`Option ${index+1} of ${options.length}`}>{index+1}/{options.length}</small><ChevronRight size={14} aria-hidden="true"/></button></div>;
}
