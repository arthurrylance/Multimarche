export function cost(y,n,b=100) { return Math.max(y,n)+b*Math.log1p(Math.exp(-Math.abs(y-n)/b)); }
export function quote(m,side,action,shares) {
  const y=Number(m.q_yes), n=Number(m.q_no), b=Number(m.liquidity);
  const delta=action==='buy'?shares:-shares;
  return Math.abs(cost(y+(side==='yes'?delta:0),n+(side==='no'?delta:0),b)-cost(y,n,b));
}
export function sharesForBudget(m,side,budget) {
  let lo=0,hi=10000;
  for(let i=0;i<60;i++) { const mid=(lo+hi)/2; if(quote(m,side,'buy',mid)>budget)hi=mid;else lo=mid; }
  return Math.floor(lo*10000)/10000;
}
