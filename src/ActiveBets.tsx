import {useEffect,useState} from 'react';
import {ArrowUpRight,ChevronLeft,ChevronRight} from 'lucide-react';
import PositionCards from './PositionCards';
import {groupPositions} from './portfolio-summary.mjs';
import type {PositionSummary} from './portfolio-summary.mjs';
export default function ActiveBets({rows,recent={},openMarket,portfolio}:{rows:PositionSummary[];recent?:Record<string,string>;openMarket:(id:string,side?:'yes'|'no')=>void;portfolio:()=>void}){
 const bets=rows.filter(r=>r.market.status!=='resolved'),lastBet=(id:string)=>Date.parse(recent[id]??'')||0,groups=groupPositions(bets).sort((a,b)=>Math.max(...b.rows.map(r=>lastBet(r.market.id)))-Math.max(...a.rows.map(r=>lastBet(r.market.id)))),[now,setNow]=useState(Date.now),[page,setPage]=useState(0),hasBets=bets.length>0;
 const pages=Math.ceil(groups.length/3),currentPage=Math.min(page,Math.max(0,pages-1)),visible=groups.slice(currentPage*3,currentPage*3+3).flatMap(g=>g.rows);
 useEffect(()=>{if(!hasBets)return;const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[hasBets]);
 if(!hasBets)return null;
 return <section className="active-bets" aria-label="Your active bets"><div className="active-bets-heading"><h2>Your bets <small title={`${bets.length} predictions across ${groups.length} markets`}>{bets.length}</small></h2><div className="bet-overview-actions">{pages>1&&<><button type="button" className="bet-scroll" aria-label="Previous 3 bets" disabled={currentPage===0} onClick={()=>setPage(Math.max(0,currentPage-1))}><ChevronLeft size={15}/></button><span className="bet-page" role="status" aria-live="polite">{currentPage+1} / {pages}</span><button type="button" className="bet-scroll" aria-label="Next 3 bets" disabled={currentPage===pages-1} onClick={()=>setPage(Math.min(pages-1,currentPage+1))}><ChevronRight size={15}/></button></>}<button className="text-button" onClick={portfolio}>View portfolio <ArrowUpRight size={14}/></button></div></div><PositionCards key={currentPage} rows={visible} openMarket={openMarket} now={now} id="home" layout="strip"/></section>;
}
