export function quoteOrder(levels,quantity,limit,action){
 let remaining=Math.max(0,Number(quantity)||0),cost=0,worst=null;const sorted=[...levels].map(l=>({price:Number(l.price),size:Number(l.size)})).sort((a,b)=>action==='buy'?a.price-b.price:b.price-a.price);
 for(const level of sorted){if(action==='buy'?level.price>limit+1e-10:level.price<limit-1e-10)continue;const take=Math.min(remaining,level.size);if(take<=0)continue;cost+=take*level.price;remaining-=take;worst=level.price;if(remaining<.00000001){remaining=0;break;}}
 const filled=Math.max(0,Number(quantity)||0)-remaining;
 return {filled,remaining,cost,average:filled?cost/filled:0,worst};
}
export function marketLimit(worst,action){
 if(worst==null)return action==='buy'?.9999:.0001;
 const ticks=action==='buy'?Math.ceil((worst*1.005-1e-10)*10000):Math.floor((worst*.995+1e-10)*10000);
 return Number(Math.min(.9999,Math.max(.0001,ticks/10000)).toFixed(4));
}
export function maxShares(levels,budget){
 let quantity=0,left=budget;
 for(const l of [...levels].sort((a,b)=>Number(a.price)-Number(b.price))){const price=Number(l.price),size=Number(l.size),take=Math.min(size,left/price);quantity+=take;left-=take*price;if(left<=1e-8)break;}
 return Math.floor(Math.min(1000000,quantity)*10000)/10000;
}
