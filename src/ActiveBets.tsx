import {useEffect,useState} from 'react';
import {ArrowUpRight} from 'lucide-react';
import PositionCards from './PositionCards';
import {groupPositions} from './portfolio-summary.mjs';
import type {PositionSummary} from './portfolio-summary.mjs';
export default function ActiveBets({rows,openMarket,portfolio}:{rows:PositionSummary[];openMarket:(id:string,side?:'yes'|'no')=>void;portfolio:()=>void}){
 const bets=rows.filter(r=>r.market.status!=='resolved'),groups=groupPositions(bets),visible=groups.slice(0,6).flatMap(g=>g.rows),[now,setNow]=useState(Date.now),hasBets=bets.length>0;
 useEffect(()=>{if(!hasBets)return;const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[hasBets]);
 if(!hasBets)return null;
 return <section className="active-bets" aria-label="Your active bets"><div className="active-bets-heading"><h2>Your bets <small>{bets.length} predictions · {groups.length} markets</small></h2><button className="text-button" onClick={portfolio}>View portfolio <ArrowUpRight size={14}/></button></div><PositionCards rows={visible} openMarket={openMarket} now={now} id="home"/><p className="bet-estimate-note">Winning shares pay ◈1 each. Payouts shown before loan repayment.{groups.length>6&&' View your portfolio for all positions.'}</p></section>;
}
