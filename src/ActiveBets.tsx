import {formatShares} from './display-format.mjs';
import {useEffect,useState} from 'react';
import {Clock3,ArrowUpRight} from 'lucide-react';
import {summarizeBets,timeRemaining} from './bet-summary.mjs';
import type {Market,Position} from './types';
const money=(n:number)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:2});
const signed=(n:number)=>`${n>=0?'+':'−'}${money(Math.abs(n))}`;
export default function ActiveBets({markets,positions,openMarket,portfolio}:{markets:Market[];positions:Position[];openMarket:(id:string)=>void;portfolio:()=>void}){
 const bets=summarizeBets(markets,positions),[now,setNow]=useState(Date.now),hasBets=bets.length>0;
 useEffect(()=>{if(!hasBets)return;const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[hasBets]);
 if(!hasBets)return null;
 return <section className="active-bets" aria-label="Your active bets"><div className="active-bets-heading"><h2>Your bets <small>{bets.length}</small></h2><button className="text-button" onClick={portfolio}>View portfolio <ArrowUpRight size={14}/></button></div><div className="active-bet-grid">{bets.slice(0,6).map(b=><button className="active-bet-card" key={b.market.id} onClick={()=>openMarket(b.market.id)}><span className="bet-time"><Clock3 size={12}/>{timeRemaining(b.market,now)}</span><b>{b.market.title}</b><span className="bet-holding">{b.yes>0&&<span className="positive">Yes · {formatShares(b.yes)} shares</span>}{b.no>0&&<span className="negative">No · {formatShares(b.no)} shares</span>}</span><span className="bet-estimate"><span>Estimated P/L</span><strong className={b.profit>=0?'positive':'negative'}>{signed(b.profit)} ◈</strong></span><span className="bet-outcomes"><span>If Yes <b className={b.ifYes>=0?'positive':'negative'}>{signed(b.ifYes)}</b></span><span>If No <b className={b.ifNo>=0?'positive':'negative'}>{signed(b.ifNo)}</b></span></span></button>)}</div><p className="bet-estimate-note">P/L uses current share prices; direction changes can execute at different prices. Yes/No figures show net profit or loss at settlement.</p></section>;
}
