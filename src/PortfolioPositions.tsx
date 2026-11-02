import {useState} from 'react';
import type {PositionSummary} from './portfolio-summary.mjs';
import {positionTotals} from './portfolio-summary.mjs';
import PositionCards,{positionMoney,positionPercent} from './PositionCards';
export default function PortfolioPositions({rows,openMarket,error}:{rows:PositionSummary[];openMarket:(id:string,side?:'yes'|'no')=>void;error:string}){
 const[filter,setFilter]=useState('open'),[search,setSearch]=useState('');
 const totals=positionTotals(rows),query=search.trim().toLowerCase(),visible=rows.filter(r=>(filter==='all'||(filter==='settled'?r.market.status==='resolved':r.market.status!=='resolved'))&&`${r.market.title} ${r.market.group_title??''} ${r.market.option_label??''}`.toLowerCase().includes(query));
 return <section className="portfolio-holdings" aria-label="Your positions">
  <div className="portfolio-stats position-stats"><div><span>Invested in open positions</span><strong>{positionMoney(totals.basis)}</strong><small>{totals.count} {totals.count===1?'prediction':'predictions'} · cost of shares still held</small></div><div><span>Potential payout</span><strong>{positionMoney(totals.payout)}</strong><small>If each market's best outcome wins</small></div><div><span>Potential profit</span><strong className={totals.profit===null?'muted':totals.profit<0?'negative':'positive'}>{positionMoney(totals.profit,true)}</strong><small>Payout minus invested credits</small></div><div><span>Potential return</span><strong className={totals.percent===null?'muted':totals.percent<0?'negative':'positive'}>{positionPercent(totals.percent)}</strong><small>Profit ÷ invested credits</small></div></div>
  <div className="holdings-heading"><h2 className="section-title">Your positions</h2><span>{visible.length} {visible.length===1?'prediction':'predictions'}</span></div>
  <div className="holdings-filters"><div role="group" aria-label="Filter positions">{['open','settled','all'].map(value=><button key={value} aria-pressed={filter===value} onClick={()=>setFilter(value)}>{value==='open'?'Open':value==='settled'?'Settled':'All'}</button>)}</div><input type="search" aria-label="Search your positions" placeholder="Find a position…" value={search} onChange={e=>setSearch(e.target.value)}/></div>
  {error&&<p className="form-error" role="alert">{error}</p>}
  {visible.length?<PositionCards rows={visible} openMarket={openMarket} id="portfolio"/>:<div className="empty"><h3>{query?'No matching positions.':filter==='open'?'No open positions.':filter==='settled'?'No settled positions.':'No positions yet.'}</h3><p>{query?'Try another search.':filter==='open'?'Your matched predictions appear here. Settled positions are in the Settled filter.':'Buy shares in a market to get started.'}</p></div>}
  <p className="holding-note">Winning shares pay ◈1 each. Payouts are before loan repayment; potential totals assume the highest-payout outcome wins in every open market. Invested credits exclude pending bets and shares already sold.</p>
 </section>;
}
