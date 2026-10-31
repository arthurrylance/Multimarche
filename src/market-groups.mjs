export function groupOptions(markets,groupId){return markets.filter(m=>m.group_id===groupId&&!m.history_deleted_at).slice().sort((a,b)=>(a.group_position??0)-(b.group_position??0));}
export function marketListings(markets,watched=[],sort='Trending',search='',now=Date.now()){
 const stars=new Set(watched),visible=markets.filter(m=>!m.archived&&!m.history_deleted_at),entries=new Map(),query=search.trim().toLowerCase();
 for(const m of visible){const key=m.group_id?`group:${m.group_id}`:`market:${m.id}`;if(!entries.has(key))entries.set(key,{key,groupId:m.group_id??null,title:m.group_title||m.title,markets:[]});entries.get(key).markets.push(m);}
 const matches=m=>(!query||`${m.title} ${m.group_title??''} ${m.option_label??''}`.toLowerCase().includes(query))&&(sort==='Resolved'?m.status==='resolved':sort==='Awaiting result'?m.status==='proposed'||(m.status==='open'&&Date.parse(m.closes_at)<=now):m.status!=='resolved');
 return [...entries.values()].filter(e=>e.markets.some(matches)).map(e=>{
  e.markets.sort((a,b)=>(a.group_position??0)-(b.group_position??0));e.openId=e.markets.find(matches).id;e.watched=e.markets.some(m=>stars.has(m.id));e.volume=e.markets.reduce((s,m)=>s+Number(m.volume),0);e.createdAt=Math.max(...e.markets.map(m=>Date.parse(m.created_at)));const active=e.markets.filter(m=>m.status!=='resolved');e.closesAt=Math.min(...(active.length?active:e.markets).map(m=>Date.parse(m.closes_at)));return e;
 }).sort((a,b)=>Number(b.watched)-Number(a.watched)||(sort==='Newest'?b.createdAt-a.createdAt:sort==='Ending soon'?a.closesAt-b.closesAt:b.volume-a.volume));
}
