import {useEffect,useRef,useState} from 'react';
import {dateInputDisplay,parseDateInput,dateInputDraft} from './display-format.mjs';
export function DateInput({value,onChange,label,min,required=false,disabled=false}:{value:string;onChange:(value:string)=>void;label:string;min?:string;required?:boolean;disabled?:boolean}){
 const[draft,setDraft]=useState(()=>dateInputDisplay(value)),emitted=useRef(value),input=useRef<HTMLInputElement>(null);
 useEffect(()=>{if(value!==emitted.current){emitted.current=value;setDraft(dateInputDisplay(value));}},[value]);
 const validity=(text:string)=>{const day=parseDateInput(text);return text&&!day?'Enter a valid date as dd/mm/yyyy.':day&&min&&day<min?`Choose ${dateInputDisplay(min)} or later.`:'';};
 useEffect(()=>{input.current?.setCustomValidity(validity(draft));},[draft,min]);
 return <input ref={input} type="text" inputMode="numeric" aria-label={label} placeholder="dd/mm/yyyy" aria-invalid={draft?!!validity(draft):undefined} pattern="[0-9]{2}/[0-9]{2}/[0-9]{4}" maxLength={10} value={draft} required={required} disabled={disabled} onChange={e=>{const text=dateInputDraft(e.target.value);setDraft(text);e.currentTarget.setCustomValidity(validity(text));const next=parseDateInput(text)??'';emitted.current=next;onChange(next);}}/>;
}
export function DateTimeInput({value,onChange,label,disabled=false}:{value:string;onChange:(value:string)=>void;label:string;disabled?:boolean}){
 const[day='',time='']=value.split('T');
 const change=(date:string,clock:string)=>onChange(date||clock?`${date}T${clock}`:'');
 return <div className="local-date-time" role="group" aria-label={label}><label><span>Date</span><DateInput value={day} onChange={date=>change(date,time)} label={`${label} date`} required={!!time} disabled={disabled}/></label><label><span>Time</span><input type="time" aria-label={`${label} time`} value={time} required={!!day} disabled={disabled} onChange={e=>change(day,e.target.value)}/></label></div>;
}
