import {useEffect,useState} from 'react';
import {supabase} from './db';
import {formatDate,formatDateTime} from './display-format.mjs';
type Entry={id:string;reason:string;amount:number;created_at:string;game:string|null;day:string|null;spent:number;received:number;transactions:number};
const names:Record<string,string>={snake:'Snake',plinko:'Plinko',roulette:'Roulette',blackjack:'Blackjack'};
const fmt=(n:number)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:4});
export default function CreditHistory({userId,tick}:{userId:string;tick:number}){
 const[snapshot,setSnapshot]=useState<{owner:string;entries:Entry[]}>({owner:'',entries:[]}),[error,setError]=useState(''),[loading,setLoading]=useState(true),[retry,setRetry]=useState(0);
 useEffect(()=>{let active=true;setLoading(true);setError('');void(async()=>{try{const{data,error}=await supabase.rpc('portfolio_history',{p_limit:100});if(error)throw error;if(active)setSnapshot({owner:userId,entries:data??[]});}catch(e){if(active)setError((e as {message?:string}).message||'Could not load credit history.');}finally{if(active)setLoading(false);}})();return()=>{active=false;};},[userId,tick,retry]);
 const entries=snapshot.owner===userId?snapshot.entries:[];
 return <section className="credit-history"><h2 className="section-title">Credit history <small>Games grouped by day</small></h2>{error&&<p className="form-error" role="alert">{error} <button type="button" className="text-button" onClick={()=>setRetry(value=>value+1)}>Retry</button></p>}<div className="activity-list">{entries.map(entry=><div key={entry.id}><span>{entry.game?`${names[entry.game]||entry.game} · ${formatDate(entry.day!)}`:entry.reason}<small>{entry.game?Number(entry.spent)>0?`Net for day · spent ◈ ${fmt(entry.spent)} · returned ◈ ${fmt(entry.received)}`:`Earned ◈ ${fmt(entry.received)}`:formatDateTime(entry.created_at)}</small></span><b className={Number(entry.amount)>0?'green-text':Number(entry.amount)<0?'red-text':''}>{Number(entry.amount)>0?'+':Number(entry.amount)<0?'−':''}◈ {fmt(Math.abs(Number(entry.amount)))}</b></div>)}{!entries.length&&!error&&<p className="section-note muted" role="status">{loading?'Loading credit history…':'No credit history yet.'}</p>}</div></section>;
}
