import {useEffect,useRef,useState} from 'react';
import {ArrowUpRight,ChevronLeft,ChevronRight} from 'lucide-react';
import PositionCards from './PositionCards';
import {groupPositions} from './portfolio-summary.mjs';
import type {PositionSummary} from './portfolio-summary.mjs';
export default function ActiveBets({rows,openMarket,portfolio}:{rows:PositionSummary[];openMarket:(id:string,side?:'yes'|'no')=>void;portfolio:()=>void}){
 const bets=rows.filter(r=>r.market.status!=='resolved'),groups=groupPositions(bets),[now,setNow]=useState(Date.now),strip=useRef<HTMLDivElement>(null),hasBets=bets.length>0;
 const scroll=(direction:number)=>{const element=strip.current;if(element)element.scrollBy({left:direction*(element.clientWidth+12)});};
 useEffect(()=>{if(!hasBets)return;const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[hasBets]);
 if(!hasBets)return null;
 return <section className="active-bets" aria-label="Your active bets"><div className="active-bets-heading"><h2>Your bets <small title={`${bets.length} predictions across ${groups.length} markets`}>{bets.length}</small></h2><div className="bet-overview-actions">{groups.length>3&&<><button type="button" className="bet-scroll" aria-label="Scroll bets left" onClick={()=>scroll(-1)}><ChevronLeft size={15}/></button><button type="button" className="bet-scroll" aria-label="Scroll bets right" onClick={()=>scroll(1)}><ChevronRight size={15}/></button></>}<button className="text-button" onClick={portfolio}>View portfolio <ArrowUpRight size={14}/></button></div></div><PositionCards rows={bets} openMarket={openMarket} now={now} id="home" layout="strip" scrollRef={strip}/></section>;
}
