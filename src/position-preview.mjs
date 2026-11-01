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

// Independent holdings: buying never closes the other side.
export function portfolioPosition({market,yes=0,no=0,basisYes=0,basisNo=0,debt=0,bidsYes=[],bidsNo=[]}){
 const book=market.execution_model==='clob';
 const y=book?quoteOrder(bidsYes,yes,.0001,'sell'):{filled:yes,cost:quote(market,'yes','sell',yes)};
 const afterYes={...market,q_yes:Number(market.q_yes)-yes};
 const n=book?quoteOrder(bidsNo,no,.0001,'sell'):{filled:no,cost:quote(afterYes,'no','sell',no)};
 const basis=basisYes+basisNo,full=y.filled+epsilon>=yes&&n.filled+epsilon>=no;
 return{yesShares:yes,noShares:no,basisYes,basisNo,basis,debt,now:{return:full?y.cost+n.cost-debt:null,profit:full?y.cost+n.cost-basis:null},yes:{return:yes-debt,profit:yes-basis},no:{return:no-debt,profit:no-basis}};
}
export function projectTrade({market,yes=0,no=0,basisYes=0,basisNo=0,side,action,quantity,limit=0,levels=[],tif='GTC',debt=0,draw=0,hasPending=false}){
 const book=market.execution_model==='clob',buy=action==='buy';
 const fill=book?quoteOrder(levels,quantity,limit,action):{filled:quantity,cost:quote(market,side,action,quantity)};
 const failed=book&&tif==='FOK'&&fill.filled+epsilon<quantity;
 const matched=failed?0:fill.filled,planned=book&&(tif==='FAK'||failed)?matched:quantity,pending=Math.max(0,planned-matched);
 const nowCost=failed?0:fill.cost,fullCost=nowCost+pending*limit,owned=side==='yes'?yes:no,basis=side==='yes'?basisYes:basisNo;
 const basisRemoved=q=>owned>epsilon?basis*q/owned:0;
 const next=q=>({yes:yes+(side==='yes'?(buy?q:-q):0),no:no+(side==='no'?(buy?q:-q):0)});
 const immediate=next(matched),final=next(planned);
 const nextBasis=buy?basis+fullCost:Math.max(0,basis-basisRemoved(planned));
 const totalBasis=(side==='yes'?basisNo:basisYes)+nextBasis;
 const borrowed=failed?0:draw,newDebt=debt+borrowed;
 const repayNow=!hasPending&&pending<epsilon&&immediate.yes<epsilon&&immediate.no<epsilon?newDebt:0;
 const finalDebt=!hasPending&&final.yes<epsilon&&final.no<epsilon?0:newDebt;
 const reserved=buy?pending*limit:0,cash=(buy?-nowCost:nowCost)+borrowed-repayNow;
 return{yesShares:Math.max(0,final.yes),noShares:Math.max(0,final.no),basis:totalBasis,change:`${buy?'Adds to':'Reduces'} ${side==='yes'?'Yes':'No'}`,cash,availableCash:cash-reserved,realised:buy?0:nowCost-basisRemoved(matched),reserved,pending,matched,failed,debt:finalDebt,yes:{return:Math.max(0,final.yes)-finalDebt,profit:Math.max(0,final.yes)-totalBasis},no:{return:Math.max(0,final.no)-finalDebt,profit:Math.max(0,final.no)-totalBasis}};
}
