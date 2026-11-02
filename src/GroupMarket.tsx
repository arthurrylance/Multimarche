import {formatDateTime} from './display-format.mjs';
import {useState} from 'react';
import PredictionSelect from './PredictionSelect';
import {Star,ArrowLeft,ArrowUpRight} from 'lucide-react';
import type {Market} from './types';
import type {MarketListing} from './market-groups.mjs';
const fmt=(n:number,d=0)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:d});
const sharePrice=(n:number)=>`◈ ${n>0&&n<.0001?'<0.0001':fmt(n,4)}`;
const status=(m:Market)=>m.status==='resolved'?`Resolved ${m.outcome?.toUpperCase()}`:m.resolution_disputed?'Disputed':m.status==='proposed'?'Confirm result':m.paused?'Paused':Date.parse(m.closes_at)<=Date.now()?'Trading ended':'';
const price=(m:Market)=>m.status==='resolved'?m.outcome?.toUpperCase():`${fmt(m.probability*100)}%`;
export function GroupMarketCard({listing:g,open,watched,watch}:{listing:MarketListing;open:(id:string,side?:'yes'|'no')=>void;watched:string[];watch:(id:string)=>void}){
 const[selection,setSelection]=useState({start:g.openId,id:g.openId}),selected=selection.start===g.openId?selection.id:g.openId,m=g.markets.find(m=>m.id===selected)??g.markets.find(m=>m.id===g.openId)??g.markets[0],resolved=g.markets.filter(m=>m.status==='resolved').length,panel=`listing-${g.groupId||g.openId}`;
 const setSelected=(id:string)=>setSelection({start:g.openId,id});
 return <article className="market-card group-market-card" onClick={e=>{if(!(e.target as Element).closest('button,a,input,select,textarea'))open(m.id);}}>
  <div className="card-top"><button className="market-title" title={g.title} onClick={()=>open(m.id)}>{g.title}</button><button className={`watch-button ${watched.includes(m.id)?'watched':''}`} aria-label={`${watched.includes(m.id)?'Unstar':'Star'} ${m.option_label||m.title}`} onClick={()=>watch(m.id)}><Star size={16} fill={watched.includes(m.id)?'currentColor':'none'}/></button></div>
  <div className="card-options" aria-hidden="true"/>
  <div className="card-body" id={`${panel}-panel`}>
   <div className="card-prob"><div><strong className={m.status==='resolved'?(m.outcome==='yes'?'positive':m.outcome==='no'?'negative':''):''}>{m.status==='resolved'?m.outcome?.toUpperCase():<>{fmt(m.probability*100)}<span>%</span></>}</strong><span className="chance-label">{m.status==='resolved'?'Result':m.execution_model==='clob'?(m.price_available===false?'Starting estimate':'Yes price'):'chance'}</span></div><PredictionSelect label={`Predictions in ${g.title}`} controls={`${panel}-panel`} value={m.id} onChange={setSelected} options={g.markets.map(option=>({id:option.id,label:option.option_label||option.title,detail:price(option)}))}/></div>
   <div className="card-context"><span title="Independent options · more than one can happen">{g.markets.length} independent options</span><span title={m.counter_enabled?`${m.counter_label||'Count'}: ${fmt(m.counter_value??0)}${status(m)?' · '+status(m):''}`:status(m)}>{m.counter_enabled?`${m.counter_label||'Count'}: ${fmt(m.counter_value??0)}${status(m)?' · '+status(m):''}`:status(m)}</span></div>
   <div className={`outcomes ${m.status==='resolved'?'resolved-outcomes':''}`}>{m.status==='resolved'?<button className="secondary" onClick={()=>open(m.id)}>View result</button>:<><button className="yes-button" onClick={()=>open(m.id,'yes')}>Yes <span>{m.price_available===false?'Place order':sharePrice(m.probability)}<ArrowUpRight size={13}/></span></button><button className="no-button" onClick={()=>open(m.id,'no')}>No <span>{m.price_available===false?'Place order':sharePrice(1-m.probability)}<ArrowUpRight size={13}/></span></button></>}</div>
  </div>
  <div className="card-bottom"><span title={`◈ ${fmt(g.volume,2)} Vol.`}>◈ {fmt(g.volume,2)} Vol.</span><span title={formatDateTime(g.closesAt)}>{resolved===g.markets.length?'All resolved':resolved?`${resolved}/${g.markets.length} resolved`:formatDateTime(g.closesAt)}</span></div>
 </article>;
}
export function GroupNavigator({title,markets,selected,open,back}:{title:string;markets:Market[];selected:string;open:(id:string)=>void;back:()=>void}){
 return <section className="group-navigation"><button className="back-button" onClick={back}><ArrowLeft size={16}/>All markets</button><h1>{title}</h1><p className="group-independence">Each option is a separate Yes/No bet. Several can win.</p><nav aria-label="Options in this market" className="group-option-tabs">{markets.map(m=><button key={m.id} aria-pressed={selected===m.id} onClick={()=>open(m.id)}><span>{m.option_label||m.title}</span><b>{price(m)}</b><small>{status(m)}</small></button>)}</nav></section>;
}
