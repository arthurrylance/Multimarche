import {useState} from 'react';
import {ArrowUpRight} from 'lucide-react';
import {formatShares} from './display-format.mjs';
import {timeRemaining} from './bet-summary.mjs';
import {groupPositions} from './portfolio-summary.mjs';
import type {PositionGroup,PositionSummary} from './portfolio-summary.mjs';
import OptionTabs from './OptionTabs';
const fmt=(n:number)=>n.toLocaleString(undefined,{maximumFractionDigits:2});
export const positionMoney=(n:number|null,signed=false)=>n===null?'—':`${n<0?'−':signed&&n>0?'+':''}◈ ${fmt(Math.abs(n))}`;
export const positionPercent=(n:number|null)=>n===null?'—':`${n>0?'+':''}${fmt(n)}%`;
const tone=(n:number|null)=>n===null?'muted':n>=0?'positive':'negative';
function PositionCard({group,openMarket,now,id}:{group:PositionGroup;openMarket:(id:string,side?:'yes'|'no')=>void;now:number;id:string}){
 const[selected,setSelected]=useState(group.rows[0].market.id),row=group.rows.find(r=>r.market.id===selected)??group.rows[0],m=row.market,settled=m.status==='resolved';
 const panel=`${id}-${m.group_id||m.id}`;
 return <article className="holding-card">
  <div className="holding-card-heading"><h3>{group.title}</h3>{group.rows.length>1&&<small>{group.rows.length} positions</small>}</div>
  {group.rows.length>1&&<OptionTabs id={panel} label={`Positions in ${group.title}`} options={group.rows.map(r=>({id:r.market.id,label:r.market.option_label||r.market.title}))} selected={m.id} select={setSelected}/>}
  <div id={`${panel}-panel`} role={group.rows.length>1?'tabpanel':undefined} aria-labelledby={group.rows.length>1?`${panel}-tab-${m.id}`:undefined}>
   <button type="button" className="holding-open" onClick={()=>openMarket(m.id,row.yes>0?'yes':'no')}><span>{m.group_id?m.option_label||m.title:'View market'}</span><ArrowUpRight size={15}/></button>
   <p className="bet-time">{settled?`Settled · ${m.outcome==='void'?'Refunded':m.outcome?.toUpperCase()}`:timeRemaining(m,now)}</p>
   <div className="holding-sides">{(['yes','no'] as const).filter(s=>row[s]>0).map(s=><button key={s} onClick={()=>openMarket(m.id,s)}><b className={s==='yes'?'positive':'negative'}>{s==='yes'?'Yes':'No'}</b><span>{formatShares(row[s])} shares</span>{row[s==='yes'?'reservedYes':'reservedNo']>0&&<small>{formatShares(row[s==='yes'?'reservedYes':'reservedNo'])} reserved</small>}</button>)}</div>
   {!settled&&<><dl className="holding-metrics"><div><dt>Invested</dt><dd>{positionMoney(row.basis)}</dd></div><div><dt>Current value (est.)</dt><dd>{positionMoney(row.value)}</dd></div><div><dt>Profit / loss (est.)</dt><dd className={tone(row.profit)}>{positionMoney(row.profit,true)}</dd></div><div><dt>Return</dt><dd className={tone(row.percent)}>{positionPercent(row.percent)}</dd></div></dl>{row.value===null&&<p className="holding-note">No traded price yet. Value and return will appear when a price is available.</p>}</>}
  </div>
 </article>;
}
export default function PositionCards({rows,openMarket,now=Date.now(),id='positions'}:{rows:PositionSummary[];openMarket:(id:string,side?:'yes'|'no')=>void;now?:number;id?:string}){
 return <div className="holding-grid">{groupPositions(rows).map(group=><PositionCard key={group.key} group={group} openMarket={openMarket} now={now} id={id}/>)}</div>;
}
