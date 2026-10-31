export function cost(y,n,b=100) { return Math.max(y,n)+b*Math.log1p(Math.exp(-Math.abs(y-n)/b)); }
export function quote(m,side,action,shares) {
  const y=Number(m.q_yes), n=Number(m.q_no), b=Number(m.liquidity),prior=Number(m.initial_probability??.5);
  const delta=action==='buy'?shares:-shares;
  const oy=prior===.5?0:b*Math.log(prior),on=prior===.5?0:b*Math.log1p(-prior);
  return Math.abs(cost(y+oy+(side==='yes'?delta:0),n+on+(side==='no'?delta:0),b)-cost(y+oy,n+on,b));
}
export function sharesForBudget(m,side,budget) {
  let lo=0,hi=10000;
  for(let i=0;i<60;i++) { const mid=(lo+hi)/2; if(quote(m,side,'buy',mid)>budget)hi=mid;else lo=mid; }
  return Math.floor(lo*10000)/10000;
}

// A direction purchase is equivalent to closing opposite units at 1 minus its price.
export function netPreview(held,netCost,side,quantity,total) {
 const direction=side==='yes'?1:-1,closing=Math.min(Math.max(0,-held*direction),quantity);
 const signed=held+direction*quantity,cash=closing-total,remainingCost=netCost-cash;
 return {side:signed>0?'YES':signed<0?'NO':'',shares:Math.abs(signed),cash,yes:Math.max(0,signed)-remainingCost,no:Math.max(0,-signed)-remainingCost};
}
