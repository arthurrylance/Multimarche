import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './db';
import Modal from './Modal';
import {OrdersList} from './MyOrders';
import {automaticPrice} from './quick-bet.mjs';
import {quoteOrder} from './orderbook.mjs';
import {sharesForBudget,quote,netPreview} from './math.mjs';
import type {BookLevel} from './orderbook.mjs';
import type {Market,Position,BookOrder} from './types';
import {requiresTradeConfirmation} from './interactions.mjs';
import {schoolDateTime} from './ending-times.mjs';
type Snapshot={bids:Record<string,BookLevel[]>;asks:Record<string,BookLevel[]>;executable_asks:Record<string,BookLevel[]>;orders:BookOrder[]};
type Loan={market_id:string;factor:number;remaining:number};
type Intent={p_market:string;p_side:'yes'|'no';p_budget:number;p_factor:number;p_price:number|null;p_tif:string;p_expires:string|null;p_min_shares:number;p_request:string;quantity:number;cash:number;finalSide:string;finalShares:number;yes:number;no:number;returnValue:number;profit:number;borrowed:number};
const fmt=(n:number,d=2)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:d});
export default function BookTrading({userId,market:m,side,setSide,balance,positions,frozen,tick,refresh,notify}:{userId:string;market:Market;side:'yes'|'no';setSide:(s:'yes'|'no')=>void;balance:number;positions:Position[];frozen:boolean;tick:number;refresh:()=>void;notify:(s:string)=>void}){
 const isBook=m.execution_model==='clob';
 const[book,setBook]=useState<Snapshot|null>(null),[loan,setLoan]=useState<Loan|null>(null),[loaded,setLoaded]=useState(false),[advanced,setAdvanced]=useState(false),[customPrice,setCustomPrice]=useState(false),[budget,setBudget]=useState('25'),[factor,setFactor]=useState(1),[price,setPrice]=useState(String(Number(side==='yes'?m.probability:1-m.probability).toFixed(4))),[tif,setTif]=useState('GTC'),[expiry,setExpiry]=useState('');
 const[busy,setBusy]=useState(false),[error,setError]=useState(''),[review,setReview]=useState<Intent|null>(null),[warning,setWarning]=useState<{intent:Intent;loss:number;ratio:number;key:string}|null>(null);
 const flight=useRef(false),nonce=useRef<{key:string;id:string}|null>(null);
 const closeReview=useCallback(()=>setReview(null),[]),closeWarning=useCallback(()=>setWarning(null),[]);
 useEffect(()=>{setPrice(String(Number(side==='yes'?m.probability:1-m.probability).toFixed(4)));setError('');},[side,m.id]);
 useEffect(()=>{
  let active=true;
  const load=async()=>{try{
   const [orders,loans]=await Promise.all([isBook?supabase.rpc('orderbook',{p_market:m.id}):Promise.resolve({data:null,error:null}),supabase.from('leverage_positions').select('market_id,factor,remaining').eq('status','active').eq('user_id',userId).maybeSingle()]);
   if(!active)return;if(orders.error)throw orders.error;if(loans.error)throw loans.error;setBook(orders.data);setLoan(loans.data);if(loans.data)setFactor(1);setLoaded(true);
  }catch(e){if(active){setLoaded(false);setError((e as {message?:string}).message||'Could not load your position.');}}};
  void load();return()=>{active=false;};
 },[m.id,userId,tick,isBook]);
 const current=positions.filter(p=>p.market_id===m.id),held=current.reduce((s,p)=>s+(p.side==='yes'?1:-1)*Number(p.shares),0),netCost=current.reduce((s,p)=>s+Number(p.net_cost),0);
 const levels=book?.executable_asks[side]??[];
 const limit=isBook?(customPrice?Number(price):automaticPrice(levels,'buy',side==='yes'?m.probability:1-m.probability)):null;
 const exposure=Number(budget)*factor,qty=isBook?Math.floor(exposure/Math.max(.0001,limit??0)*10000)/10000:sharesForBudget(m,side,exposure);
 const total=isBook?qty*(limit??0):quote(m,side,'buy',qty);
 const preview=netPreview(held,netCost,side,qty,total);
 const matching=isBook?quoteOrder(levels,qty,limit??0,'buy'):null;
 const cashHold=isBook?Math.max(0,total-Math.min(side==='yes'?Math.max(0,-held):Math.max(0,held),qty)):Math.max(0,-preview.cash);
 const valid=Number.isFinite(exposure)&&exposure>0&&qty>=.0001&&qty<=(isBook?1000000:10000)&&(!isBook||(Number.isFinite(limit)&&limit!>=.0001&&limit!<=.9999&&Math.abs(limit!*10000-Math.round(limit!*10000))<1e-6));
 const opposite=side==='yes'?Math.max(0,-held):Math.max(0,held);
 const enough=factor>1?Number(budget)<=balance:cashHold<=Math.max(0,balance)+1e-8&&(balance>=0||qty<=opposite);
 const borrowed=loan?.market_id===m.id?Number(loan.remaining):factor>1?exposure-Number(budget):0;
 const repayNow=loan?.market_id===m.id&&preview.shares<.00000001?borrowed:0,cashNow=preview.cash-repayNow;
 const returnValue=Math.max(0,preview.cash)+(preview.side===side.toUpperCase()?preview.shares:0)-borrowed,profit=side==='yes'?preview.yes:preview.no;
 const canLeverage=!loan&&Math.abs(held)<.00000001;
 const isOpen=!frozen&&m.status==='open'&&!m.paused&&!m.archived&&!m.history_deleted_at&&Date.parse(m.closes_at)>Date.now();
 const submit=async(intent:Intent)=>{
  if(flight.current)return;flight.current=true;setBusy(true);setError('');
  try{
   const{quantity:_,cash:__,finalSide:___,finalShares:____,yes:_____,no:______,returnValue:_return,profit:_profit,borrowed:_borrowed,...args}=intent;
   const{data,error}=await supabase.rpc('predict',args);if(error)throw error;
   nonce.current=null;setReview(null);setFactor(1);refresh();
   notify(isBook&&data?.status==='open'?'Prediction placed. Unmatched amounts are waiting.':'Position updated.');
  }catch(e){setError((e as {message?:string}).message||'Could not place prediction.');}finally{flight.current=false;setBusy(false);}
 };
 const reviewOrSubmit=(intent:Intent)=>{if(intent.p_factor>1||requiresTradeConfirmation(Math.round(intent.p_budget*intent.p_factor*100)/100,balance))setReview(intent);else void submit(intent);};
 const prepare=async()=>{
  if(flight.current||!loaded||!valid||!enough||!isOpen||(factor>1&&!canLeverage))return;setError('');let expires:string|null=null;
  if(isBook&&tif==='GTD'){try{expires=schoolDateTime(expiry).toISOString();}catch{setError('Choose an expiry in Europe/Zurich.');return;}}
  const fields={p_market:m.id,p_side:side,p_budget:Number(budget),p_factor:factor,p_price:limit,p_tif:isBook?tif:'GTC',p_expires:expires,p_min_shares:isBook?0:Math.floor(qty*.995*10000)/10000};
  const key=JSON.stringify(fields);if(nonce.current?.key!==key)nonce.current={key,id:crypto.randomUUID()};
  const intent:Intent={...fields,p_request:nonce.current.id,quantity:qty,cash:cashNow,finalSide:preview.side,finalShares:preview.shares,yes:preview.yes,no:preview.no,returnValue,profit,borrowed};
  flight.current=true;setBusy(true);
  try{
   const{data,error}=await supabase.rpc('loss_summary');if(error)throw error;
   let acknowledged='';try{acknowledged=sessionStorage.getItem(`multimarche-loss-${userId}`)||'';}catch{}
   if(data?.triggered&&acknowledged!==data.key){setWarning({intent,loss:data.loss,ratio:data.ratio,key:data.key});return;}
  }catch(e){setError((e as {message?:string}).message||'Could not check recent results.');return;}finally{flight.current=false;setBusy(false);}
  reviewOrSubmit(intent);
 };
 const continueWarning=()=>{if(!warning)return;try{sessionStorage.setItem(`multimarche-loss-${userId}`,warning.key);}catch{}const intent=warning.intent;setWarning(null);reviewOrSubmit(intent);};
 const cancel=async(id:string|null)=>{if(flight.current)return;flight.current=true;setBusy(true);try{const{error}=id?await supabase.rpc('cancel_order',{p_order:id}):await supabase.rpc('cancel_my_orders',{p_market:m.id});if(error)throw error;refresh();notify('Unmatched amount released.');}catch(e){setError((e as {message?:string}).message||'Could not cancel.');}finally{flight.current=false;setBusy(false);}};
 const result=(label:string,value:number)=><div><span>{label}</span><b className={value>=0?'positive':'negative'}>{value>=0?'+':'−'}◈ {fmt(Math.abs(value))}</b></div>;
 return <aside className="trade-panel book-trading simple-trading clean-bet-panel">
  <h3 className="bet-panel-title">Place a bet</h3>
  <div className="trade-side"><button className={`yes-button ${side==='yes'?'chosen':''}`} aria-pressed={side==='yes'} onClick={()=>setSide('yes')}>Yes</button><button className={`no-button ${side==='no'?'chosen':''}`} aria-pressed={side==='no'} onClick={()=>setSide('no')}>No</button></div>
  <label className="quick-amount-label"><span className="bet-amount-heading">Amount <small>Available ◈ {fmt(balance)}</small></span><span>◈<input aria-label="Credits to bet" type="number" inputMode="decimal" min="0.01" step="0.01" value={budget} onChange={e=>setBudget(e.target.value)}/></span></label>
  <div className="amount-presets">{[10,25,100].map(n=><button key={n} onClick={()=>setBudget(String(n))}>◈ {n}</button>)}<button onClick={()=>setBudget(String(Math.max(0,Math.floor(balance*100)/100)))}>Max</button></div>
  {valid&&<div className="trade-summary simple-bet-summary"><div className="potential"><span>{held!==0?'Total return':'To win'} if {side==='yes'?'Yes':'No'}{isBook&&<small>if matched</small>}</span><strong className={returnValue<0?'negative':''}>{returnValue<0?'−':''}◈ {fmt(Math.abs(returnValue))}</strong></div>{result(held!==0?'Total profit':'Profit',profit)}{preview.cash>0&&<div><span>{cashNow>=0?'Returned now':'Balance change now'}{isBook?' if matched':''}</span><b className={cashNow<0?'negative':''}>{cashNow<0?'−':''}◈ {fmt(Math.abs(cashNow))}</b></div>}</div>}
  {error&&<p className="form-error" role="alert">{error}</p>}
  <button className={`full trade-submit ${side==='yes'?'yes-submit':'no-submit'}`} disabled={busy||!loaded||!isOpen||!valid||!enough||(factor>1&&!canLeverage)} onClick={()=>void prepare()}>{frozen?'Account timed out':!isOpen?'Betting closed':busy?'Placing…':!loaded?'Loading…':!enough?'Insufficient credits':`Bet ${side==='yes'?'Yes':'No'}${factor>1?` · ${factor}×`:''}`}</button>
  <button className="advanced-bet-toggle" aria-expanded={advanced} aria-controls={`advanced-${m.id}`} onClick={()=>setAdvanced(!advanced)}>{advanced?'Hide advanced':'Advanced'}<span aria-hidden="true">{advanced?'−':'+'}</span></button>
  {advanced&&<section className="advanced-bet-options" id={`advanced-${m.id}`} aria-label="Advanced betting">
   <div className="net-position"><small>Your bet</small><strong className={held>0?'positive':held<0?'negative':''}>{held===0?'No open bet':`Backing ${held>0?'Yes':'No'}`}</strong>{held!==0&&<small>◈ {fmt(Math.abs(held),0)} potential payout</small>}</div>
   <div className="trade-summary"><div><span>After this bet</span><b>{preview.shares>0?`${preview.side==='YES'?'Yes':'No'} · ◈ ${fmt(preview.shares,0)}`:'No open bet'}</b></div>{result('Net result if Yes',preview.yes)}{result('Net result if No',preview.no)}</div>
   <p className="tiny muted">Betting the opposite way reduces your old bet first, then switches sides.</p>
   <label>Leverage</label><div className="leverage-picker" role="group" aria-label="Leverage">{[1,5,10].map(n=><button key={n} aria-pressed={factor===n} disabled={n>1&&!canLeverage} onClick={()=>setFactor(n)}>{n}×</button>)}</div>
   {factor>1&&<p className="leverage-note">◈ {fmt(Number(budget))} stake + ◈ {fmt(exposure-Number(budget))} borrowed. Maximum loss ◈ {fmt(exposure)}. Losses can leave your balance negative.</p>}
   {loan&&<p className="tiny muted">One leveraged market at a time.{loan.market_id===m.id?` ◈ ${fmt(loan.remaining)} to repay.`:''}</p>}
   {!loan&&held!==0&&<p className="tiny muted">Leverage starts from no open bet.</p>}
   {isBook&&<div className="prediction-advanced"><label className="checkbox-label"><input type="checkbox" checked={customPrice} onChange={e=>setCustomPrice(e.target.checked)}/>Set a limit price</label>{customPrice&&<label>Limit price ◈<input aria-label="Limit price per share" type="number" min="0.0001" max="0.9999" step="0.0001" value={price} onChange={e=>setPrice(e.target.value)}/></label>}<label>Unmatched amount<select value={tif} onChange={e=>setTif(e.target.value)}><option value="GTC">Wait until cancelled or market closes</option><option value="GTD">Wait until a chosen time</option><option value="FOK">Fill all immediately or cancel</option><option value="FAK">Fill available now; cancel the rest</option></select></label>{tif==='GTD'&&<label>Expiry<input type="datetime-local" value={expiry} onChange={e=>setExpiry(e.target.value)}/><small>Europe/Zurich</small></label>}</div>}
   {isBook&&matching&&<p className="tiny muted">{fmt(matching.filled,0)} can match now. Unmatched amounts wait; a new bet replaces your pending orders here.</p>}
   {isBook&&<details className="compact-book"><summary>Order book</summary><section className="book-depth"><div className="depth-head"><span>Price ◈</span><span>Quantity</span></div><h4>Offers</h4>{(book?.asks[side]??[]).slice(0,8).map(l=><button key={l.price} onClick={()=>{setCustomPrice(true);setPrice(String(l.price));}}><span className="negative">{fmt(l.price,4)}</span><span>{fmt(l.size,0)}</span></button>)}<h4>Bids</h4>{(book?.bids[side]??[]).slice(0,8).map(l=><div className="depth-head" key={l.price}><span className="positive">{fmt(l.price,4)}</span><span>{fmt(l.size,0)}</span></div>)}</section></details>}
  </section>}
  {isBook&&book?.orders.some(o=>o.status==='open')&&<details className="pending-bet-details"><summary>Pending bets</summary><section className="market-open-orders"><button className="text-button" disabled={busy} onClick={()=>void cancel(null)}>Cancel all</button><OrdersList orders={book.orders} busy={busy} cancel={id=>void cancel(id)}/></section></details>}
  {review&&<Modal title="Confirm bet" onClose={closeReview}><div className="bet-review"><p>{m.title}</p><dl><div><dt>Bet</dt><dd>{review.p_side==='yes'?'Yes':'No'}{review.p_factor>1?` · ${review.p_factor}×`:''}</dd></div><div><dt>Amount</dt><dd>◈ {fmt(review.p_budget)}</dd></div><div><dt>Return if correct{isBook?' and matched':''}</dt><dd>◈ {fmt(review.returnValue)}</dd></div><div><dt>Profit</dt><dd>◈ {fmt(review.profit)}</dd></div>{review.p_factor>1&&<><div><dt>Borrowed</dt><dd>◈ {fmt(review.p_budget*(review.p_factor-1))}</dd></div><div><dt>Maximum loss</dt><dd>◈ {fmt(review.p_budget*review.p_factor)}</dd></div></>}</dl>{review.p_factor>1&&<p>Borrowing is repaid when this bet closes. Losing can leave your balance negative.</p>}{error&&<p className="form-error">{error}</p>}<div className="confirm-actions"><button className="secondary" disabled={busy} onClick={closeReview}>Cancel</button><button className="primary" disabled={busy} onClick={()=>void submit(review)}>{busy?'Placing…':'Confirm'}</button></div></div></Modal>}
  {warning&&<Modal title="Responsible gambling*" onClose={closeWarning}><div className="loss-warning"><span className="eyebrow">*Satire · virtual credits only</span><h3>You’ve lost ◈ {fmt(warning.loss)} in the last 24 hours.</h3><p>That’s {fmt(warning.ratio*100,1)}% of your bankroll. Are you sure you want to continue?</p><div className="confirm-actions"><button className="secondary" onClick={continueWarning}>Yes</button><button className="primary" onClick={continueWarning}>Hell yeah!</button></div></div></Modal>}
 </aside>;
}
