import {useState} from 'react';
import {ArrowUpRight} from 'lucide-react';
import {formatShares} from './display-format.mjs';
import {timeRemaining} from './bet-summary.mjs';
import {groupPositions} from './portfolio-summary.mjs';
import type {PositionGroup,PositionSummary} from './portfolio-summary.mjs';
import PredictionSelect from './PredictionSelect';
const fmt=(n:number)=>n.toLocaleString(undefined,{maximumFractionDigits:2});
export const positionMoney=(n:number|null,signed=false)=>n===null?'—':`${n<0?'−':signed&&n>0?'+':''}◈ ${fmt(Math.abs(n))}`;
export const positionPercent=(n:number|null)=>n===null?'—':`${n>0?'+':''}${fmt(n)}%`;
const tone=(n:number|null)=>n===null?'muted':n>=0?'positive':'negative';
function PositionCard({group,openMarket,now,id}:{group:PositionGroup;openMarket:(id:string,side?:'yes'|'no')=>void;now:number;id:string}){
 const[selected,setSelected]=useState(group.rows[0].market.id),row=group.rows.find(r=>r.market.id===selected)??group.rows[0],m=row.market,settled=m.status==='resolved';
 const panel=`${id}-${m.group_id||m.id}`;
 return <article className="holding-card" onClick={e=>{if(!(e.target as Element).closest('button,a,input,select,textarea'))openMarket(m.id,row.yes>0?'yes':'no');}}>
  <div className="holding-card-header"><div className="holding-card-heading"><h3><button type="button" className="holding-open" title={group.title} aria-label={`Open ${m.title}`} onClick={()=>openMarket(m.id,row.yes>0?'yes':'no')}><span>{group.title}</span><ArrowUpRight size={14}/></button></h3>{group.rows.length>1&&<small>{group.rows.length} options</small>}</div>
  <div className="holding-selector">{group.rows.length>1&&<PredictionSelect controls={`${panel}-panel`} label={`Positions in ${group.title}`} options={group.rows.map(r=>({id:r.market.id,label:r.market.option_label||r.market.title}))} value={m.id} onChange={setSelected}/>}
  {m.group_id&&group.rows.length===1&&<button className="holding-option" onClick={()=>openMarket(m.id,row.yes>0?'yes':'no')}>{m.option_label||m.title}</button>}</div></div>
  <div className="holding-card-content" id={`${panel}-panel`}>
   <div className="holding-context"><p className="bet-time">{settled?`Settled · ${m.outcome==='void'?'Refunded':m.outcome?.toUpperCase()}`:timeRemaining(m,now)}</p><div className="holding-sides">{(['yes','no'] as const).filter(s=>row[s]>0).map(s=><button key={s} onClick={()=>openMarket(m.id,s)}><b className={s==='yes'?'positive':'negative'}>{s==='yes'?'Yes':'No'}{!settled&&Number.isFinite(m.probability)&&<span className="holding-chance" title={m.price_available===false?'Starting estimate':'Current market chance'}>{Math.round((s==='yes'?m.probability:1-m.probability)*100)}%{m.price_available===false?' est.':''}</span>}</b><span>{formatShares(row[s])} shares</span>{row[s==='yes'?'reservedYes':'reservedNo']>0&&<small>{formatShares(row[s==='yes'?'reservedYes':'reservedNo'])} reserved</small>}</button>)}</div></div>
   {!settled&&<div className="holding-finances"><dl className="holding-investment"><div><dt>Invested</dt><dd>{positionMoney(row.basis)}</dd></div></dl>{row.outcomes.map(outcome=><section className="holding-settlement" key={outcome.side} aria-label={`If ${outcome.side==='yes'?'Yes':'No'} wins`}><h4>If <span className={outcome.side==='yes'?'positive':'negative'}>{outcome.side==='yes'?'Yes':'No'}</span> wins</h4><dl className="holding-metrics"><div><dt title="Before loan repayment">Payout</dt><dd>{positionMoney(outcome.payout)}</dd></div><div><dt>Profit / return</dt><dd className={tone(outcome.profit)}>{positionMoney(outcome.profit,true)}<small>{positionPercent(outcome.percent)}</small></dd></div></dl></section>)}{row.outcomes.length>1&&<p className="holding-note">Profit includes both sides’ cost. Only the winning side pays out.</p>}</div>}
  </div>
 </article>;
}
export default function PositionCards({rows,openMarket,now=Date.now(),id='positions',layout='grid'}:{rows:PositionSummary[];openMarket:(id:string,side?:'yes'|'no')=>void;now?:number;id?:string;layout?:'grid'|'strip'}){
 return <div className={layout==='strip'?'holding-strip':'holding-grid'}>{groupPositions(rows).map(group=><PositionCard key={group.key} group={group} openMarket={openMarket} now={now} id={id}/>)}</div>;
}
