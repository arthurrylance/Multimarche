import {useEffect,useState} from 'react';
import {supabase} from './db';
import type {BookOrder,Market} from './types';
const fmt=(n:number)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:4});
export function OrdersList({orders,busy,cancel,markets}:{orders:BookOrder[];busy:boolean;cancel:(id:string)=>void;markets?:Market[]}){
 const open=orders.filter(o=>o.status==='open');
 return <div className="open-orders">{open.map(o=><div className="open-order" key={o.id}><div>{markets&&<b>{markets.find(m=>m.id===o.market_id)?.title||'Market'}</b>}<span className={o.side==='yes'?'positive':'negative'}>{o.action.toUpperCase()} {o.side.toUpperCase()} · ◈ {fmt(o.price)}</span><small>{fmt(o.filled)} / {fmt(o.quantity)} shares filled · {o.tif}<br/>Expires {new Date(o.expires_at).toLocaleString()}</small></div><button className="text-button" disabled={busy} onClick={()=>cancel(o.id)}>Cancel</button></div>)}{!open.length&&<p className="tiny muted">No open orders.</p>}</div>;
}
export default function MyOrders({tick,markets,refresh,notify}:{tick:number;markets:Market[];refresh:()=>void;notify:(s:string)=>void}){
 const[orders,setOrders]=useState<BookOrder[]>([]),[busy,setBusy]=useState(false);
 useEffect(()=>{let active=true;supabase.rpc('get_my_orders',{p_market:null}).then(({data,error})=>{if(!active)return;if(error)notify(error.message);else setOrders(data??[]);});return()=>{active=false;};},[tick]);
 const cancel=async(id:string|null)=>{setBusy(true);const{error}=id?await supabase.rpc('cancel_order',{p_order:id}):await supabase.rpc('cancel_my_orders',{p_market:null});setBusy(false);if(error)notify(error.message);else{refresh();notify('Unfilled reservations released.');}};
 return <section className="portfolio-orders"><div className="active-bets-heading"><h2>Your open orders</h2>{orders.some(o=>o.status==='open')&&<button className="text-button" disabled={busy} onClick={()=>void cancel(null)}>Cancel all</button>}</div><OrdersList orders={orders} busy={busy} cancel={id=>void cancel(id)} markets={markets}/></section>;
}
