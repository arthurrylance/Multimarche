// Purchase cost is the basis of the remaining shares, supplied by position_accounting.
// net_cost includes proceeds from past sales and must not be used as this basis.
export function positionSummaries(markets,positions,costs={}){
 const rows=new Map();
 for(const p of positions){
  if(Number(p.shares)<=0)continue;
  const market=markets.find(m=>m.id===p.market_id);if(!market||market.history_deleted_at)continue;
  if(!rows.has(market.id))rows.set(market.id,{market,yes:0,no:0,reservedYes:0,reservedNo:0});
  const row=rows.get(market.id);row[p.side]+=Number(p.shares);row[p.side==='yes'?'reservedYes':'reservedNo']+=Number(p.reserved_shares??0);
 }
 return [...rows.values()].map(row=>{
  const cost=costs[row.market.id],basis=cost&&Number.isFinite(Number(cost.yes))&&Number.isFinite(Number(cost.no))?Number(cost.yes)+Number(cost.no):null;
  const outcomes=['yes','no'].filter(side=>row[side]>0).map(side=>{
   const payout=row[side],profit=basis!==null?payout-basis:null;
   return {side,payout,profit,percent:profit!==null&&basis>0?profit/basis*100:null};
  });
  // Yes and No are alternative settlements, so the best case cannot add both payouts.
  const payout=Math.max(row.yes,row.no),profit=basis!==null?payout-basis:null;
  return {...row,basis,outcomes,payout,profit,percent:profit!==null&&basis>0?profit/basis*100:null};
 }).sort((a,b)=>Number(a.market.status==='resolved')-Number(b.market.status==='resolved')||Date.parse(a.market.closes_at)-Date.parse(b.market.closes_at));
}
export function groupPositions(rows){
 const groups=new Map();
 for(const row of rows){const m=row.market,key=m.group_id?`group:${m.group_id}`:`market:${m.id}`;
  if(!groups.has(key))groups.set(key,{key,title:m.group_title||m.title,rows:[]});groups.get(key).rows.push(row);
 }
 return [...groups.values()].map(group=>({...group,rows:group.rows.slice().sort((a,b)=>(a.market.group_position??0)-(b.market.group_position??0))}));
}
export function positionTotals(rows){
 const active=rows.filter(r=>r.market.status!=='resolved'),basis=active.every(r=>r.basis!==null)?active.reduce((sum,r)=>sum+r.basis,0):null;
 const payout=active.reduce((sum,r)=>sum+r.payout,0),profit=basis!==null?payout-basis:null;
 return {count:active.length,basis,payout,profit,percent:profit!==null&&basis>0?profit/basis*100:null};
}
