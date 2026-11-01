import {quantityForCredits} from './quick-bet.mjs';
import {marketLimit,maxShares,quoteOrder} from './orderbook.mjs';

// Market orders cap the reservation at the entered budget. Price improvement and
// an unfilled FAK remainder are released by the server, never left on the book.
export function bookQuote({levels,action,amount,mode,price}){
 const buy=action==='buy',budget=Number(amount);
 let limit=Number(price);
 if(mode==='market'){
  const target=buy?maxShares(levels,Math.max(0,budget)):Math.max(0,budget);
  const depth=quoteOrder(levels,target,buy?.9999:.0001,action);
  limit=marketLimit(depth.worst,action);
 }
 const quantity=buy?quantityForCredits(budget,limit):budget;
 return{limit,quantity,...quoteOrder(levels,quantity,limit,action)};
}
