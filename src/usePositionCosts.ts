import {useEffect,useState} from 'react';
import {supabase} from './db';
import type {Market,Position} from './types';
import type {PositionCosts} from './portfolio-summary.mjs';
export default function usePositionCosts(userId:string|undefined,markets:Market[],positions:Position[],tick:number){
 const ids=[...new Set(positions.filter(p=>Number(p.shares)>0&&markets.some(m=>m.id===p.market_id&&m.status!=='resolved'&&!m.history_deleted_at)).map(p=>p.market_id))].sort();
 const signature=JSON.stringify(positions.filter(p=>ids.includes(p.market_id)).map(p=>[p.market_id,p.side,p.shares,p.net_cost]));
 const key=JSON.stringify([userId,signature]);
 const[snapshot,setSnapshot]=useState<{key:string;costs:PositionCosts;recent:Record<string,string>;error:string}>({key:'',costs:{},recent:{},error:''});
 const idsKey=JSON.stringify(ids);
 useEffect(()=>{
  let active=true;
  if(!userId)return;
  const load=async()=>{
   const requested=JSON.parse(idsKey) as string[],costs:PositionCosts={},recent:Record<string,string>={};let failed=false,next=0;
   const loadRecent=async()=>{
    if(!requested.length)return;
    try{const{data,error}=await supabase.from('markets').select('id,trades(created_at)').in('id',requested).eq('trades.user_id',userId).eq('trades.action','buy').order('created_at',{referencedTable:'trades',ascending:false}).limit(1,{referencedTable:'trades'});if(error)throw error;for(const row of data??[]){const at=row.trades?.[0]?.created_at;if(at)recent[row.id]=at;}}catch{/* Cost and payout displays still work if recency cannot be loaded. */}
   };
   // Reuse the authenticated accounting RPC, with bounded parallelism for larger portfolios.
   const recentRequest=loadRecent();
   await Promise.all(Array.from({length:Math.min(6,requested.length)},async()=>{
    while(active&&next<requested.length){const id=requested[next++];try{const{data,error}=await supabase.rpc('position_accounting',{p_market:id});if(error)throw error;if(!data||!Number.isFinite(Number(data.yes))||!Number.isFinite(Number(data.no)))throw Error('Missing purchase costs');costs[id]={yes:Number(data.yes),no:Number(data.no)};}catch{failed=true;}}
   }));
   if(active)setSnapshot({key,costs,recent:{...recent},error:failed?'Some purchase costs could not be loaded. Refresh to retry.':''});
   await recentRequest;if(active)setSnapshot(previous=>previous.key===key?{...previous,recent}:previous);
  };
  void load();return()=>{active=false;};
 },[userId,key,idsKey,tick]);
 return snapshot.key===key?snapshot:{key,costs:{},recent:{},error:''};
}
