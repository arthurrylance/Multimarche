import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './db';
import Modal from './Modal';
import {OrdersList} from './MyOrders';
import {quoteOrder,marketLimit} from './orderbook.mjs';
import {automaticPrice,quantityForCredits,sellFraction} from './quick-bet.mjs';
import type {BookLevel} from './orderbook.mjs';
import type {Market,Position,BookOrder} from './types';
import {requiresTradeConfirmation} from './interactions.mjs';
import {schoolDateTime} from './ending-times.mjs';
type Snapshot={bids:Record<string,BookLevel[]>;asks:Record<string,BookLevel[]>;executable_bids:Record<string,BookLevel[]>;executable_asks:Record<string,BookLevel[]>;orders:BookOrder[];price_available?:boolean;price?:number};
type Intent={p_market:string;p_side:string;p_action:string;p_price:number;p_quantity:number;p_tif:string;p_expires:string|null;p_request:string;simple:boolean};
const fmt=(n:number,d=4)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:d});
export default function BookTrading({userId,market:m,side,setSide,balance,positions,frozen,tick,refresh,notify}:{userId:string;market:Market;side:'yes'|'no';setSide:(s:'yes'|'no')=>void;balance:number;positions:Position[];frozen:boolean;tick:number;refresh:()=>void;notify:(s:string)=>void}){
 const[book,setBook]=useState<Snapshot|null>(null),[action,setAction]=useState<'buy'|'sell'>('buy'),[advanced,setAdvanced]=useState(false),[budget,setBudget]=useState('25'),[fraction,setFraction]=useState(100);
 const[type,setType]=useState('limit'),[price,setPrice]=useState('0.5'),[quantity,setQuantity]=useState('25'),[tif,setTif]=useState('GTC'),[expiry,setExpiry]=useState(''),[partial,setPartial]=useState(false);
 const[busy,setBusy]=useState(false),[error,setError]=useState(''),[review,setReview]=useState<Intent|null>(null),[warning,setWarning]=useState<{intent:Intent;loss:number;ratio:number;key:string}|null>(null);
 const flight=useRef(false),nonce=useRef<{key:string;id:string}|null>(null);
 const closeReview=useCallback(()=>setReview(null),[]),closeWarning=useCallback(()=>setWarning(null),[]);
 useEffect(()=>{setPrice(String(Number((side==='yes'?m.probability:1-m.probability).toFixed(4))||.5));setError('');},[side,m.id]);
 useEffect(()=>{
  let active=true;
  const load=async()=>{try{const{data,error}=await supabase.rpc('orderbook',{p_market:m.id});if(!active)return;if(error)setError(error.message);else setBook(data);}catch{if(active)setError('Could not load bets. Try again in a moment.');}};
  void load();const timer=setInterval(()=>void load(),5000);return()=>{active=false;clearInterval(timer);};
 },[m.id,tick]);
 const position=positions.find(p=>p.market_id===m.id&&p.side===side),available=Number(position?.shares??0)-Number(position?.reserved_shares??0);
 const levels=(action==='buy'?book?.executable_asks[side]:book?.executable_bids[side])??[];
 const marked=book?.price_available?Number(book.price):m.price_available!==false?m.probability:.5;
 const autoPrice=automaticPrice(levels,action,side==='yes'?marked:1-marked);
 const raw=quoteOrder(levels,Number(quantity),action==='buy'?.9999:.0001,action);
 const limit=advanced?(type==='market'?marketLimit(raw.worst,action):Number(price)):autoPrice;
 const qty=advanced?Number(quantity):action==='buy'?quantityForCredits(budget,limit):sellFraction(available,fraction);
 const quote=quoteOrder(levels,qty,limit,action),maxCost=qty*limit,maximumBudget=Math.floor(Math.min(balance,limit*1000000)*100)/100;
 const isOpen=!frozen&&m.status==='open'&&!m.paused&&!m.archived&&!m.history_deleted_at&&Date.parse(m.closes_at)>Date.now();
 const valid=Number.isFinite(qty)&&qty>=.0001&&qty<=1000000&&Math.abs(qty*10000-Math.round(qty*10000))<1e-6&&Number.isFinite(limit)&&limit>=.0001&&limit<=.9999&&Math.abs(limit*10000-Math.round(limit*10000))<1e-6;
 const enough=action==='buy'?(advanced?maxCost:Number(budget))<=balance+1e-9:qty<=available+1e-9;
 const liquid=!advanced||type==='limit'||(quote.filled>0&&(partial||quote.remaining<.00000001));
 const submit=async(intent:Intent)=>{
  if(flight.current)return;flight.current=true;setBusy(true);setError('');
  try{
   const{simple,...args}=intent;
   const{data,error}=await supabase.rpc('place_order',args);if(error)throw error;
   nonce.current=null;setReview(null);refresh();const order=data as BookOrder;
   if(simple){
    const waiting=Number(order.remaining)*Number(order.price);
    notify(order.status==='open'?`${intent.p_action==='buy'?'Bet placed':'Cash-out requested'} · ◈ ${fmt(waiting,2)} waiting for a match.`:intent.p_action==='buy'?'Bet placed.':'Cash-out complete.');
   }else notify(order.status==='open'?`${fmt(order.filled)} filled · ${fmt(order.remaining)} shares waiting on the book.`:order.status==='filled'?`Order filled: ${fmt(order.filled)} shares.`:`${fmt(order.filled)} shares filled. Unfilled amount cancelled.`);
  }catch(e){setError((e as {message?:string}).message||'Could not place bet.');}finally{flight.current=false;setBusy(false);}
 };
 const reviewOrSubmit=(intent:Intent)=>{if(requiresTradeConfirmation(Math.round(intent.p_price*intent.p_quantity*100)/100,balance))setReview(intent);else void submit(intent);};
 const prepare=async()=>{
  if(flight.current||!valid||!enough||!liquid||!isOpen)return;setError('');let expires:string|null=null;
  if(advanced&&type==='limit'&&tif==='GTD'){try{expires=schoolDateTime(expiry).toISOString();}catch{setError('Choose an order expiry in Europe/Zurich.');return;}}
  const fields={p_market:m.id,p_side:side,p_action:action,p_price:limit,p_quantity:qty,p_tif:advanced?(type==='market'?(partial?'FAK':'FOK'):tif):'GTC',p_expires:expires};
  const key=JSON.stringify(fields);if(nonce.current?.key!==key)nonce.current={key,id:crypto.randomUUID()};const intent={...fields,p_request:nonce.current.id,simple:!advanced};
  if(action==='buy'){
   let data;flight.current=true;setBusy(true);
   try{const result=await supabase.rpc('loss_summary');if(result.error)throw result.error;data=result.data;}catch(e){setError((e as {message?:string}).message||'Could not check recent results.');return;}finally{flight.current=false;setBusy(false);}
   let acknowledged='';try{acknowledged=sessionStorage.getItem(`multimarche-loss-${userId}`)||'';}catch{}
   if(data?.triggered&&acknowledged!==data.key){setWarning({intent,loss:data.loss,ratio:data.ratio,key:data.key});return;}
  }
  reviewOrSubmit(intent);
 };
 const continueWarning=()=>{if(!warning)return;try{sessionStorage.setItem(`multimarche-loss-${userId}`,warning.key);}catch{}setWarning(null);reviewOrSubmit(warning.intent);};
 const cancel=async(id:string|null)=>{
  if(flight.current)return;flight.current=true;setBusy(true);
  try{const{error}=id?await supabase.rpc('cancel_order',{p_order:id}):await supabase.rpc('cancel_my_orders',{p_market:m.id});if(error)throw error;refresh();notify('Unmatched part cancelled and released.');}catch(e){setError((e as {message?:string}).message||'Could not cancel bet.');}finally{flight.current=false;setBusy(false);}
 };
 const max=()=>{
  if(!advanced){setBudget(String(maximumBudget));return;}
  if(action==='sell'){setQuantity(String(available));return;}
  if(type==='limit'){setQuantity(String(Math.floor(Math.min(1000000,balance/Math.max(.0001,limit))*10000)/10000));return;}
  let low=0,high=Math.min(1000000,levels.reduce((sum,l)=>sum+Number(l.size),0));
  for(let i=0;i<50;i++){const mid=(low+high)/2,q=quoteOrder(levels,mid,.9999,'buy');if(mid*marketLimit(q.worst,'buy')<=balance)low=mid;else high=mid;}
  setQuantity(String(Math.floor(low*10000)/10000));
 };
 const chooseLevel=(p:number,next:'buy'|'sell')=>{setAction(next);setType('limit');setPrice(String(p));setError('');};
 const switchMode=()=>{setAdvanced(!advanced);setError('');};
 return <aside className={`trade-panel book-trading ${advanced?'advanced-trading':'simple-trading'}`}>
  <div className="trade-tabs"><button className={action==='buy'?'active':''} onClick={()=>{setAction('buy');setError('');}}>{advanced?'Buy':'Bet'}</button><button className={action==='sell'?'active':''} onClick={()=>{setAction('sell');setError('');}}>{advanced?'Sell':'Cash out'}</button><button className="trading-mode" aria-expanded={advanced} onClick={switchMode}>{advanced?'Simple':'Advanced'}</button></div>
  <div className="trade-side"><button className={`yes-button ${side==='yes'?'chosen':''}`} aria-pressed={side==='yes'} onClick={()=>setSide('yes')}>Yes</button><button className={`no-button ${side==='no'?'chosen':''}`} aria-pressed={side==='no'} onClick={()=>setSide('no')}>No</button></div>
  {advanced?<>
   <div className="order-type"><button aria-pressed={type==='limit'} onClick={()=>setType('limit')}>Limit</button><button aria-pressed={type==='market'} onClick={()=>setType('market')}>Market</button></div>
   {type==='limit'&&<label>Limit price per share <span>◈<input aria-label="Limit price per share" type="number" min="0.0001" max="0.9999" step="0.0001" value={price} onChange={e=>{setPrice(e.target.value);setError('');}}/></span></label>}
   <label>Shares<input aria-label="Order quantity in shares" type="number" min="0.0001" max="1000000" step="0.0001" value={quantity} onChange={e=>{setQuantity(e.target.value);setError('');}}/></label>
   <div className="amount-presets">{[10,25,100].map(n=><button key={n} onClick={()=>setQuantity(String(n))}>{n}</button>)}<button onClick={max}>Max</button></div>
   <p className="order-available">Available: {action==='buy'?`◈ ${fmt(balance,2)}`:`${fmt(available)} ${side.toUpperCase()} shares`}</p>
   {type==='limit'?<><label>Unfilled orders<select value={tif} onChange={e=>setTif(e.target.value)}><option value="GTC">Wait until cancelled or market closes</option><option value="GTD">Expire at a chosen time</option></select></label>{tif==='GTD'&&<label>Order expires<input type="datetime-local" value={expiry} onChange={e=>setExpiry(e.target.value)}/><small>Europe/Zurich · before market close</small></label>}</>:<label className="checkbox-label"><input type="checkbox" checked={partial} onChange={e=>setPartial(e.target.checked)}/>Allow partial fill; cancel the rest</label>}
   <div className="trade-summary"><div><span>{action==='buy'?'Maximum credits reserved':'Minimum sale price per share'}</span><b>◈ {fmt(action==='buy'?maxCost:limit,4)}</b></div><div><span>Available to fill now</span><b>{fmt(quote.filled)} / {fmt(qty||0)} shares</b></div><div><span>{action==='buy'?'Estimated immediate cost':'Estimated immediate proceeds'}</span><b>◈ {fmt(quote.cost,4)}</b></div><div className="potential"><span>{action==='buy'?'Total payout if all filled and correct':'Minimum sale proceeds if all filled'}</span><strong>◈ {fmt(action==='buy'?qty||0:maxCost||0,2)}</strong></div></div>
  </>:<>
   {action==='buy'?<><label className="quick-amount-label">Amount <span>◈<input aria-label="Credits to bet" type="number" inputMode="decimal" min="0.01" max={maximumBudget} step="0.01" value={budget} onChange={e=>{setBudget(e.target.value);setError('');}}/></span></label><div className="amount-presets">{[10,25,100].map(n=><button key={n} onClick={()=>setBudget(String(n))}>◈ {n}</button>)}<button onClick={max}>Max</button></div><p className="order-available">Available ◈ {fmt(balance,2)}</p></>:<><p className="quick-cashout-label">How much of your {side.toUpperCase()} bet?</p><div className="cashout-presets">{[25,50,100].map(n=><button key={n} aria-pressed={fraction===n} onClick={()=>setFraction(n)}>{n===100?'All':`${n}%`}</button>)}</div>{available<=0&&<p className="order-available">You have no available {side.toUpperCase()} bet to cash out.</p>}</>}
   <div className="trade-summary quick-summary"><div><span>{action==='buy'?'Stake':'Cash-out value if fully matched'}</span><b>◈ {fmt(maxCost,2)}</b></div>{action==='buy'&&<><div className="potential"><span>If {side==='yes'?'Yes':'No'} wins, you get</span><strong>◈ {fmt(qty,2)}</strong></div><div><span>Profit</span><b className="positive">+◈ {fmt(qty-maxCost,2)}</b></div></>}</div>
   {book&&valid&&quote.remaining>0&&<p className="quick-match-note">{quote.filled>0?`◈ ${fmt(quote.cost,2)} can match now. The rest will wait.`:'This will wait for someone to take the other side.'}{action==='buy'?' Only matched bets count towards your payout.':''}</p>}
   {!advanced&&action==='buy'&&Number(budget)>maximumBudget&&maximumBudget<balance&&<p className="form-error">Maximum ◈ {fmt(maximumBudget,2)} at this price.</p>}
  </>}
  {error&&<p className="form-error" role="alert">{error}</p>}
  <button className={`full trade-submit ${side==='yes'?'yes-submit':'no-submit'}`} disabled={busy||!book||!isOpen||!valid||!enough||!liquid} onClick={()=>void prepare()}>{frozen?'Account timed out':!isOpen?'Betting closed':busy?'Placing…':!book?'Loading…':!enough?'Insufficient available credits/bet':!advanced?`${action==='buy'?'Bet':'Cash out'} ${side==='yes'?'Yes':'No'}`:!liquid?'No matching liquidity':type==='limit'?'Place limit order':partial?'Fill available':'Fill entire order'}</button>
  <p className="trade-disclaimer">{advanced?(type==='limit'?'Unfilled orders reserve credits or shares until cancelled or expired.':'Immediate orders only use available opposing orders. Price protection: 0.5% beyond the quoted worst price.'):'Unmatched bets wait until cancelled or betting closes. No fees.'}</p>
  {advanced&&<section className="book-depth"><h3>{side.toUpperCase()} order book</h3><div className="depth-head"><span>Price ◈</span><span>Shares</span></div><h4>Sell orders</h4>{(book?.asks[side]??[]).slice(0,8).reverse().map(l=><button key={l.price} onClick={()=>chooseLevel(Number(l.price),'buy')}><span className="negative">{fmt(l.price)}</span><span>{fmt(l.size)}</span></button>)}{!book?.asks[side]?.length&&<p>No sell orders</p>}<h4>Buy orders</h4>{(book?.bids[side]??[]).slice(0,8).map(l=><button key={l.price} onClick={()=>chooseLevel(Number(l.price),'sell')}><span className="positive">{fmt(l.price)}</span><span>{fmt(l.size)}</span></button>)}{!book?.bids[side]?.length&&<p>No buy orders</p>}</section>}
  <section className="market-open-orders"><div className="active-bets-heading"><h3>{advanced?'Your orders':'Pending bets'}</h3>{book?.orders.some(o=>o.status==='open')&&<button className="text-button" disabled={busy} onClick={()=>void cancel(null)}>Cancel all</button>}</div><OrdersList orders={book?.orders??[]} simple={!advanced} busy={busy} cancel={id=>void cancel(id)}/>{advanced&&book&&book.orders.some(o=>o.status!=='open')&&<details><summary>Recent completed orders</summary>{book.orders.filter(o=>o.status!=='open').slice(0,10).map(o=><p className="order-receipt" key={o.id}>{o.action.toUpperCase()} {o.side.toUpperCase()} · {fmt(o.filled)} / {fmt(o.quantity)} filled · {o.status}</p>)}</details>}</section>
  {review&&<Modal title={review.simple?'Confirm bet':'Review order'} onClose={closeReview}><div className="bet-review"><p>{m.title}</p><dl>{review.simple?<><div><dt>{review.p_action==='buy'?'Bet':'Cash out'}</dt><dd>{review.p_side.toUpperCase()}</dd></div><div><dt>{review.p_action==='buy'?'Maximum stake':'Value if fully matched'}</dt><dd>◈ {fmt(review.p_price*review.p_quantity,2)}</dd></div>{review.p_action==='buy'&&<div><dt>If fully matched and correct, you get</dt><dd>◈ {fmt(review.p_quantity,2)}</dd></div>}</>:<><div><dt>Order</dt><dd>{review.p_action.toUpperCase()} {review.p_side.toUpperCase()} · {review.p_tif}</dd></div><div><dt>Shares requested</dt><dd>{fmt(review.p_quantity)}</dd></div><div><dt>{review.p_action==='buy'?'Maximum price':'Minimum price'}</dt><dd>◈ {fmt(review.p_price)}</dd></div><div><dt>{review.p_action==='buy'?'Maximum cash reserved':'Minimum total if all sold'}</dt><dd>◈ {fmt(review.p_price*review.p_quantity,4)}</dd></div></>}</dl><p className="tiny muted">{review.simple?'Unmatched amounts wait and can be cancelled. Cashing out gives up the later payout.':'Only matched shares receive a payout. Unfilled limit orders wait; immediate orders cancel any unfilled remainder. Sold shares give up their later payout.'}</p>{error&&<p className="form-error">{error}</p>}<div className="confirm-actions"><button className="secondary" disabled={busy} onClick={closeReview}>Cancel</button><button className="primary" disabled={busy} onClick={()=>void submit(review)}>{busy?'Placing…':review.simple?'Confirm':'Confirm order'}</button></div></div></Modal>}
  {warning&&<Modal title="Responsible gambling*" onClose={closeWarning}><div className="loss-warning"><span className="eyebrow">*Satire · virtual credits only</span><h3>You’ve lost ◈ {fmt(warning.loss,2)} in the last 24 hours.</h3><p>That’s {fmt(warning.ratio*100,1)}% of your bankroll. Are you sure you want to continue?</p><div className="confirm-actions"><button className="secondary" onClick={continueWarning}>Yes</button><button className="primary" onClick={continueWarning}>Hell yeah!</button></div></div></Modal>}
 </aside>;
}
