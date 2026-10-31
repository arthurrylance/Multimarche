export function summarizeBets(markets,positions){
 const byMarket=new Map(markets.filter(m=>m.status!=='resolved').map(m=>[m.id,{market:m,yes:0,no:0,netCost:0}]));
 for(const p of positions){const item=byMarket.get(p.market_id);if(!item)continue;item[p.side]+=Number(p.shares);item.netCost+=Number(p.net_cost);}
 return [...byMarket.values()].filter(p=>p.yes+p.no>0).map(p=>{
  const value=p.yes*Number(p.market.probability)+p.no*(1-Number(p.market.probability));
  return {...p,value,profit:value-p.netCost,ifYes:p.yes-p.netCost,ifNo:p.no-p.netCost};
 }).sort((a,b)=>Date.parse(a.market.closes_at)-Date.parse(b.market.closes_at));
}
export function timeRemaining(market,now=Date.now()){
 if(market.status==='proposed')return 'Awaiting confirmation';
 const seconds=Math.max(0,Math.ceil((Date.parse(market.closes_at)-now)/1000));
 if(seconds===0)return 'Awaiting result';
 const days=Math.floor(seconds/86400),hours=Math.floor(seconds%86400/3600),minutes=Math.floor(seconds%3600/60),remaining=seconds%60;
 const time=days?`${days}d ${hours}h`:hours?`${hours}h ${minutes}m`:`${minutes}m ${remaining}s`;
 return `${market.paused?'Paused · ':''}${time} left`;
}
