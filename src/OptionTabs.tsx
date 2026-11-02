export default function OptionTabs({options,selected,select,label,id}:{options:{id:string;label:string;detail?:string}[];selected:string;select:(id:string)=>void;label:string;id:string}){
 return <div className="prediction-tabs" role="tablist" aria-label={label} onKeyDown={e=>{
  if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;
  const current=options.findIndex(o=>o.id===selected),index=e.key==='Home'?0:e.key==='End'?options.length-1:(current+(e.key==='ArrowRight'?1:-1)+options.length)%options.length;
  e.preventDefault();select(options[index].id);e.currentTarget.querySelectorAll<HTMLButtonElement>('[role="tab"]')[index]?.focus();
 }}>{options.map(o=><button key={o.id} type="button" role="tab" id={`${id}-tab-${o.id}`} aria-selected={selected===o.id} aria-controls={`${id}-panel`} tabIndex={selected===o.id?0:-1} onClick={()=>select(o.id)}><span>{o.label}</span>{o.detail&&<small>{o.detail}</small>}</button>)}</div>;
}
