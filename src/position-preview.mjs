import {quote} from './math.mjs';
import {quoteOrder} from './orderbook.mjs';
const epsilon=1e-7;
export function positionChange(held,next){if(Math.abs(next-held)<epsilon)return 'No position change';if(Math.abs(next)<epsilon)return 'Closes position';if(Math.abs(held)<epsilon)return `Opens ${next>0?'Yes':'No'}`;if(held*next<0)return `Switches to ${next>0?'Yes':'No'}`;return Math.abs(next)>Math.abs(held)?`Adds to ${next>0?'Yes':'No'}`:`Reduces ${next>0?'Yes':'No'}`;}
export function currentPosition({market,held,basis,debt=0,bids=[]}){
 const shares=Math.abs(held),side=held>0?'yes':'no';const sale=market.execution_model==='clob'?quoteOrder(bids,shares,.0001,'sell'):{filled:shares,cost:quote(market,side,'sell',shares)};
 const full=sale.filled+epsilon>=shares;
 return{side,shares,basis,debt,now:{return:full?sale.cost-debt:null,profit:full?sale.cost-basis:null},yes:{return:Math.max(0,held)-debt,profit:Math.max(0,held)-basis},no:{return:Math.max(0,-held)-debt,profit:Math.max(0,-held)-basis},liquidShares:sale.filled,liquidReturn:sale.cost};
}
export function projectPosition({market,held,basis,side,quantity,limit=0,levels=[],tif='GTC',debt=0,draw=0,releasedReserve=0}){
 const book=market.execution_model==='clob',sign=side==='yes'?1:-1,opposite=Math.max(0,-held*sign);
 const matched=book?quoteOrder(levels,quantity,limit,'buy'):{filled:quantity};const failed=book&&tif==='FOK'&&matched.filled+epsilon<quantity;
 const immediate=failed?0:matched.filled,planned=book&&(tif==='FAK'||failed)?immediate:quantity;
 const costFor=q=>{const fill=quoteOrder(levels,q,limit,'buy');return fill.cost+Math.max(0,q-fill.filled)*limit;};
 const leg=q=>{const closed=Math.min(opposite,q);let proceeds=0,paid=0;if(book){proceeds=closed-costFor(closed);paid=costFor(q)-costFor(closed);}else{if(closed)proceeds=quote(market,held>0?'yes':'no','sell',closed);const next={...market,q_yes:Number(market.q_yes)-(held>0?closed:0),q_no:Number(market.q_no)-(held<0?closed:0)};paid=quote(next,side,'buy',Math.max(0,q-closed));}const allocated=Math.abs(held)>epsilon?basis*closed/Math.abs(held):0;return{closed,proceeds,paid,realised:proceeds-allocated,basis:Math.max(0,basis-allocated)+paid,net:held+sign*q};};
 const full=leg(planned),now=leg(immediate),pending=Math.max(0,planned-immediate),newDebt=debt+draw;
 const repaidNow=Math.abs(now.net)<epsilon&&pending<epsilon?newDebt:0,finalDebt=Math.abs(full.net)<epsilon?0:newDebt;
 const reserved=book?Math.max(0,pending*limit-Math.min(pending,Math.max(0,opposite-now.closed))):0;
 const cash=now.proceeds-now.paid+draw-repaidNow;
 return{side:full.net>epsilon?'YES':full.net< -epsilon?'NO':'',shares:Math.abs(full.net)<epsilon?0:Math.abs(full.net),basis:full.basis,change:positionChange(held,full.net),cash:failed?0:cash,availableCash:failed?0:cash-reserved+releasedReserve,realised:now.realised,reserved,pending,matched:immediate,planned,failed,debt:finalDebt,yes:{return:Math.max(0,full.net)-finalDebt,profit:Math.max(0,full.net)-full.basis},no:{return:Math.max(0,-full.net)-finalDebt,profit:Math.max(0,-full.net)-full.basis}};
}
