import {DateTimeInput} from './DateInput';
import {formatShares} from './display-format.mjs';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './db';
import Modal from './Modal';
import {OrdersList} from './MyOrders';
import {bookQuote} from './trading-quote.mjs';
import {quoteOrder} from './orderbook.mjs';
import {sharesForBudget,quote} from './math.mjs';
import {projectTrade} from './position-preview.mjs';
import type {TradeProjection} from './position-preview.mjs';
import {ExistingHoldings,PredictionPreview,TradeReview} from './PositionSummary';
import type {BookLevel} from './orderbook.mjs';
import type {Market,Position,BookOrder} from './types';
import {requiresTradeConfirmation} from './interactions.mjs';
import {schoolDateTime} from './ending-times.mjs';
type Snapshot={bids:Record<string,BookLevel[]>;asks:Record<string,BookLevel[]>;executable_asks:Record<string,BookLevel[]>;executable_bids?:Record<string,BookLevel[]>;orders:BookOrder[]};
type Loan={market_id:string;factor:number;remaining:number};
type Intent={p_market:string;p_side:'yes'|'no';p_action:'buy'|'sell';p_amount:number;p_factor:number;p_price:number|null;p_tif:string;p_expires:string|null;p_min_return:number;p_min_shares:number;p_request:string;projection:TradeProjection;quote:{shares:number;total:number;mode:string;repaid:number}};
const fmt=(n:number,d=2)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:d});
export default function BookTrading({userId,market:m,side,setSide,balance,positions,frozen,tick,refresh,notify}:{userId:string;market:Market;side:'yes'|'no';setSide:(s:'yes'|'no')=>void;balance:number;positions:Position[];frozen:boolean;tick:number;refresh:()=>void;notify:(s:string)=>void}){
 const isBook=m.execution_model==='clob';
 const[action,setAction]=useState<'buy'|'sell'>('buy');
 const[book,setBook]=useState<Snapshot|null>(null),[loan,setLoan]=useState<Loan|null>(null),[loaded,setLoaded]=useState(false),[advanced,setAdvanced]=useState(false),[orderMode,setOrderMode]=useState<'market'|'limit'>('market'),[budget,setBudget]=useState('25'),[factor,setFactor]=useState(1),[price,setPrice]=useState(String(Number(side==='yes'?m.probability:1-m.probability).toFixed(4))),[tif,setTif]=useState('GTC'),[expiry,setExpiry]=useState('');
 const[busy,setBusy]=useState(false),[error,setError]=useState(''),[review,setReview]=useState<Intent|null>(null),[warning,setWarning]=useState<{intent:Intent;loss:number;ratio:number;key:string}|null>(null);
 const[accounting,setAccounting]=useState<Record<string,number>|null>(null);
 const flight=useRef(false),nonce=useRef<{key:string;id:string}|null>(null);
 const closeReview=useCallback(()=>setReview(null),[]),closeWarning=useCallback(()=>setWarning(null),[]);
 useEffect(()=>{setPrice(String(Number(side==='yes'?m.probability:1-m.probability).toFixed(4)));setError('');},[side,m.id]);
 useEffect(()=>{
  let active=true;
  const load=async()=>{try{
   const [orders,loans,costs]=await Promise.all([isBook?supabase.rpc('orderbook',{p_market:m.id}):Promise.resolve({data:null,error:null}),supabase.from('leverage_positions').select('market_id,factor,remaining').eq('status','active').eq('user_id',userId).maybeSingle(),supabase.rpc('position_accounting',{p_market:m.id})]);
   if(!active)return;if(orders.error)throw orders.error;if(loans.error)throw loans.error;if(costs.error)throw costs.error;setAccounting(costs.data);setBook(orders.data);setLoan(loans.data);if(loans.data)setFactor(1);setLoaded(true);
  }catch(e){if(active){setLoaded(false);setError((e as {message?:string}).message||'Could not load your position.');}}};
  void load();return()=>{active=false;};
 },[m.id,userId,tick,isBook]);
 const current=positions.filter(p=>p.market_id===m.id),yes=Number(current.find(p=>p.side==='yes')?.shares??0),no=Number(current.find(p=>p.side==='no')?.shares??0);
 const available=Math.max(0,(side==='yes'?yes:no)-Number(current.find(p=>p.side===side)?.reserved_shares??0));
 const basisYes=Number(accounting?.yes??Math.max(0,Number(current.find(p=>p.side==='yes')?.net_cost??0))),basisNo=Number(accounting?.no??Math.max(0,Number(current.find(p=>p.side==='no')?.net_cost??0)));
 const buying=action==='buy',multiplier=buying?factor:1;
 const levels=(buying?book?.executable_asks[side]:book?.executable_bids?.[side])??[];
 const exposure=Number(budget)*multiplier;
 const bookEstimate=bookQuote({levels,action,amount:buying?exposure:Number(budget),mode:orderMode,price:Number(price)});
 const limit=isBook?bookEstimate.limit:null;
 const effectiveTif=isBook&&orderMode==='market'?'FAK':tif;
 const qty=isBook?bookEstimate.quantity:buying?sharesForBudget(m,side,exposure):Number(budget);
 const total=isBook?qty*(limit??0):quote(m,side,action,qty);
 const matching=isBook?quoteOrder(levels,qty,limit??0,action):null;
 const valid=Number.isFinite(exposure)&&exposure>0&&qty>=.0001&&qty<=(isBook?1000000:10000)&&(!buying||Math.abs(Number(budget)*100-Math.round(Number(budget)*100))<1e-6)&&(buying||Math.abs(qty*10000-Math.round(qty*10000))<1e-6)&&(!isBook||(Number.isFinite(limit)&&limit!>=.0001&&limit!<=.9999&&Math.abs(limit!*10000-Math.round(limit!*10000))<1e-6));
 const enough=buying?Number(budget)<=Math.max(0,balance)+1e-8:qty<=available+1e-8;
 const debt=loan?.market_id===m.id?Number(loan.remaining):0,hasPending=!!book?.orders.some(o=>o.status==='open');
 const projection=projectTrade({market:m,yes,no,basisYes,basisNo,side,action,quantity:Number.isFinite(qty)?qty:0,limit:Number.isFinite(limit)?limit!:0,levels,tif:effectiveTif,debt,draw:buying&&factor>1&&!loan&&yes+no===0?Math.max(0,exposure-Number(budget)):0,hasPending});
 const owned={yesShares:yes,noShares:no,basisYes,basisNo};
 const noLiquidity=isBook&&orderMode==='market'&&!levels.some(l=>Number(l.size)>0);
 const estimatedShares=isBook?projection.matched:qty;
 const estimatedCash=projection.cash;
 const plannedShares=projection.matched+projection.pending;
 const plannedTotal=projection.failed?0:isBook&&matching?matching.cost+projection.pending*(limit??0):total;
 const canLeverage=!loan&&yes+no<.00000001;
 const choose=(nextAction:'buy'|'sell',nextSide:'yes'|'no')=>{setAction(nextAction);setSide(nextSide);setBudget(nextAction==='buy'?'25':'');setFactor(1);setError('');};
 const isOpen=!frozen&&m.status==='open'&&!m.paused&&!m.archived&&!m.history_deleted_at&&Date.parse(m.closes_at)>Date.now();
 const submit=async(intent:Intent)=>{
  if(flight.current)return;flight.current=true;setBusy(true);setError('');
  try{
   const{projection:_,quote:__,...args}=intent;
   const{data,error}=await supabase.rpc('execute_trade',args);if(error)throw error;
   nonce.current=null;setReview(null);setFactor(1);setBudget('');setLoaded(false);refresh();
   notify(isBook?(data?.status==='open'?'Limit order placed. Unmatched shares are waiting.':Number(data?.filled)>0?'Trade complete. Any unfilled amount was released.':'No shares matched. Your credits and shares were released.'):'Trade complete.');
  }catch(e){setError((e as {message?:string}).message||'Could not place trade.');}finally{flight.current=false;setBusy(false);}
 };
 const reviewOrSubmit=(intent:Intent)=>{if(intent.p_factor>1||requiresTradeConfirmation(intent.p_action==='buy'?Math.round(intent.p_amount*intent.p_factor*100)/100:Math.round((matching?.cost??total)*100)/100,balance))setReview(intent);else void submit(intent);};
 const prepare=async()=>{
  if(flight.current||!loaded||!valid||!enough||!isOpen||noLiquidity||projection.failed||(buying&&factor>1&&!canLeverage))return;setError('');let expires:string|null=null;
  if(isBook&&effectiveTif==='GTD'){try{expires=schoolDateTime(expiry).toISOString();if(Date.parse(expires)<=Date.now()||Date.parse(expires)>Date.parse(m.closes_at)){setError('Choose an expiry in the future, before this market closes.');return;}}catch{setError('Choose an expiry in Europe/Zurich.');return;}}
  const fields={p_market:m.id,p_side:side,p_action:action,p_amount:Number(budget),p_factor:multiplier,p_price:limit,p_tif:isBook?effectiveTif:'GTC',p_expires:expires,p_min_return:!isBook&&!buying?total*.995:0,p_min_shares:!isBook&&buying?Math.floor(qty*.995*10000)/10000:0};
  const key=JSON.stringify(fields);if(nonce.current?.key!==key)nonce.current={key,id:crypto.randomUUID()};
  const intent:Intent={...fields,p_request:nonce.current.id,projection,quote:{shares:plannedShares,total:plannedTotal,mode:isBook?orderMode:'automatic',repaid:buying?0:Math.max(0,debt-projection.debt)}};
  if(!buying){reviewOrSubmit(intent);return;}
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
 const durationControls=<div className="prediction-advanced"><label>Order duration<select aria-label="Order duration" value={tif} disabled={busy} onChange={e=>setTif(e.target.value)}><option value="GTC">Until cancelled or market closes</option><option value="GTD">Until a chosen time</option><option value="FOK">Fill all immediately or cancel</option><option value="FAK">Fill available now; cancel the rest</option></select></label>{tif==='GTD'&&<div className="date-time-field"><span>Expiry</span><DateTimeInput label="Order expiry" value={expiry} onChange={setExpiry} disabled={busy}/><small>Europe/Zurich</small></div>}</div>;
 return <aside className="trade-panel market-trading" aria-label="Market trading">
  <div className="market-ticket">
   <div className="market-ticket-heading"><div className="market-action-tabs" role="group" aria-label="Trade action">{(['buy','sell'] as const).map(a=><button key={a} type="button" aria-pressed={action===a} className={action===a?'active':''} disabled={busy} onClick={()=>choose(a,side)}>{a==='buy'?'Buy':'Sell'}</button>)}</div>{isBook?<label className="market-order-type"><span className="sr-only">Order type</span><select aria-label="Order type" value={orderMode} disabled={busy} onChange={e=>{setOrderMode(e.target.value as 'market'|'limit');setError('');}}><option value="market">Market</option><option value="limit">Limit</option></select></label>:null}</div>
   <div className="market-outcome-picker" role="group" aria-label="Outcome">{(['yes','no'] as const).map(s=>{
    const sideLevels=(buying?book?.executable_asks[s]:book?.executable_bids?.[s])??[],best=sideLevels.length?(buying?Math.min(...sideLevels.map(l=>Number(l.price))):Math.max(...sideLevels.map(l=>Number(l.price)))):null;
    const mark=s==='yes'?m.probability:1-m.probability;
    return <button key={s} type="button" className={`market-outcome ${s} ${side===s?'selected':''}`} aria-pressed={side===s} disabled={busy} onClick={()=>{setSide(s);if(!buying)setBudget('');setError('');}}><span>{s==='yes'?'Yes':'No'}</span><b>{isBook&&best==null?'—':`◈ ${fmt(isBook?best!:mark,4)}`}</b>{(s==='yes'?yes:no)>0&&<small>Owned {formatShares(s==='yes'?yes:no)}</small>}</button>;
   })}</div>
   <p className="market-trade-hint">{buying?'Buy shares in the outcome you believe in.':'Sell shares you own to take profit or change your position.'}</p>
   <ExistingHoldings position={owned} side={side} action={action} loading={!loaded}/>
   {isBook&&orderMode==='limit'&&<label className="market-limit-price">{buying?'Max buy price':'Min sell price'}<span>◈ <input aria-label="Limit price per share" type="number" min="0.0001" max="0.9999" step="0.0001" value={price} disabled={busy} onChange={e=>setPrice(e.target.value)}/><small>/ share</small></span></label>}
   {!buying&&isBook&&orderMode==='limit'&&<div className="market-sell-duration">{durationControls}</div>}
   <label className="market-amount-label"><span>{buying?(isBook&&orderMode==='market'?'Maximum spend':'Amount'):'Shares to sell'}<small>{buying?`Available ◈ ${fmt(balance)}`:`Available ${formatShares(available)} shares`}</small></span><div>{buying&&<span>◈</span>}<input id={`trade-amount-${m.id}`} aria-label={buying?'Credits to spend':'Shares to sell'} type="number" inputMode="decimal" placeholder="0" min={buying?'0.01':'0.0001'} step={buying?'0.01':'0.0001'} value={budget} disabled={busy} onChange={e=>setBudget(e.target.value)}/>{!buying&&<span>shares</span>}</div></label>
   <div className="market-amount-presets">{buying?<>{[10,25,100].map(n=><button type="button" key={n} disabled={busy} onClick={()=>setBudget(String(n))}>◈ {n}</button>)}<button type="button" disabled={busy} onClick={()=>setBudget(String(Math.max(0,Math.floor(balance*100)/100)))}>Max</button></>:<>{[25,50,75,100].map(n=><button type="button" key={n} disabled={busy} onClick={()=>setBudget(String(Math.floor(Math.min(available,isBook?1000000:10000)*n/100*10000)/10000))}>{n===100?'Max':`${n}%`}</button>)}</>}</div>
   {isBook&&loaded&&noLiquidity&&<div className="market-liquidity-note" role="status">No {buying?'sellers':'buyers'} available for {side==='yes'?'Yes':'No'} right now. <button type="button" disabled={busy} onClick={()=>setOrderMode('limit')}>Place a limit order</button> to choose your price and wait for a match.</div>}
   {valid&&loaded&&enough&&!noLiquidity&&<section className="market-trade-estimate" aria-label="Trade estimate">
    <dl><div><dt>Est. average price</dt><dd>◈ {fmt(plannedShares>0?plannedTotal/plannedShares:0,4)}</dd></div><div><dt>{buying?'Shares you receive':'Shares you sell'}{projection.pending>0?' if filled':''}</dt><dd>{formatShares(plannedShares)} {side==='yes'?'Yes':'No'}</dd></div>{!buying&&<div><dt>Est. sale proceeds</dt><dd>◈ {fmt(plannedTotal)}</dd></div>}</dl>
    <div className="market-payout"><span>{buying?'Payout if '+(side==='yes'?'Yes':'No')+' wins':(orderMode==='limit'&&projection.pending>0?'You receive now (matched only)':estimatedCash<0?'Cash change now':'You receive now')}<small>{buying?'1 credit per winning share':'After any loan repayment'}</small></span><strong>◈ {fmt(buying?plannedShares:estimatedCash)}</strong></div>
    {buying&&<p className="market-profit">Potential profit <b>+◈ {fmt(Math.max(0,plannedShares-plannedTotal))}</b>{factor>1&&' before loan repayment'}</p>}
    {isBook&&<p className="market-estimate-note">{projection.failed?'Not enough liquidity to fill the entire order. Reduce the amount or change the order duration.':orderMode==='market'?`${formatShares(estimatedShares)} shares can match now. Prices protected within 0.5% of the quote; unused credits are released.`:`${formatShares(projection.matched)} shares can match now. ${formatShares(projection.pending)} wait at your limit price. Estimates assume full matching.`}</p>}
    <details className="market-projection-details"><summary>Portfolio after this trade</summary><PredictionPreview value={projection} book={isBook} action={action}/></details>
   </section>}
   {error&&<p className="form-error" role="alert">{error}</p>}
   <button className={`full trade-submit market-trade-submit ${side==='yes'?'yes-submit':'no-submit'}`} disabled={busy||!loaded||!isOpen||!valid||!enough||noLiquidity||projection.failed||(buying&&factor>1&&!canLeverage)} onClick={()=>void prepare()}>{frozen?'Account timed out':!isOpen?'Trading closed':busy?'Submitting…':!loaded?'Loading…':!buying&&available<.0001?`No ${side==='yes'?'Yes':'No'} shares available`:!enough?(buying?'Insufficient credits':'Insufficient available shares'):noLiquidity?'No liquidity available':projection.failed?'Not enough shares to fill all':`${buying?(side==='yes'?yes:no)>0?'Buy more':'Buy':'Sell'} ${side==='yes'?'Yes':'No'}${buying&&factor>1?` · ${factor}×`:''}`}</button>
   <p className="market-ticket-foot">{isBook?(orderMode==='market'?'Market order · fills available shares now':'Limit order · waits for your price'):'AMM · trades instantly with the liquidity pool'}</p>
   {buying&&<details className="market-trade-settings" open={advanced} onToggle={e=>setAdvanced(e.currentTarget.open)}><summary>Trade settings</summary>{advanced&&<section className="advanced-bet-options" aria-label="Trade settings">
    {buying&&<><label>Leverage</label><div className="leverage-picker" role="group" aria-label="Leverage">{[1,5,10].map(n=><button type="button" key={n} aria-pressed={factor===n} disabled={busy||(n>1&&!canLeverage)} onClick={()=>setFactor(n)}>{n}×</button>)}</div>
    {factor>1&&<p className="leverage-note">◈ {fmt(Number(budget))} stake + ◈ {fmt(exposure-Number(budget))} borrowed. Maximum loss ◈ {fmt(exposure)}. Losses can leave your balance negative.</p>}
    {loan&&<p className="tiny muted">One leveraged market at a time.{loan.market_id===m.id?` ◈ ${fmt(loan.remaining)} to repay.`:''}</p>}
    {!loan&&yes+no>0&&<p className="tiny muted">Leverage starts from no open position.</p>}</>}
    {isBook&&orderMode==='limit'&&durationControls}
   </section>}</details>}
  </div>
  {isBook&&<details className="market-orderbook"><summary>Order book <span>{side==='yes'?'Yes':'No'}</span></summary><section className="book-depth"><div className="depth-head"><span>Price ◈</span><span>Shares</span></div><h4>Asks · buy from sellers</h4>{!(book?.asks[side]??[]).length&&<p className="tiny muted">No asks yet</p>}{(book?.asks[side]??[]).slice(0,8).map(l=><button type="button" key={l.price} aria-label={`Buy ${side} at ${l.price}`} onClick={()=>{choose('buy',side);setOrderMode('limit');setPrice(String(l.price));}}><span className="negative">{fmt(l.price,4)}</span><span>{formatShares(l.size)}</span></button>)}<h4>Bids · sell to buyers</h4>{!(book?.bids[side]??[]).length&&<p className="tiny muted">No bids yet</p>}{(book?.bids[side]??[]).slice(0,8).map(l=><button type="button" key={l.price} aria-label={`Sell ${side} at ${l.price}`} onClick={()=>{choose('sell',side);setOrderMode('limit');setPrice(String(l.price));}}><span className="positive">{fmt(l.price,4)}</span><span>{formatShares(l.size)}</span></button>)}</section></details>}
  {isBook&&book?.orders.some(o=>o.status==='open')&&<details className="market-pending-orders" open><summary>Open orders <span>{book.orders.filter(o=>o.status==='open').length}</span></summary><section className="market-open-orders"><button type="button" className="text-button" disabled={busy} onClick={()=>void cancel(null)}>Cancel all</button><OrdersList orders={book.orders} busy={busy} cancel={id=>void cancel(id)}/></section></details>}
  {review&&<Modal title={review.p_action==='buy'?'Confirm purchase':'Confirm sale'} className="trade-confirmation-modal" onClose={closeReview}><div className="trade-confirmation"><p className="trade-review-question">{m.title}</p><TradeReview action={review.p_action} side={review.p_side} amount={review.p_amount} factor={review.p_factor} price={review.p_price} expires={review.p_expires} projection={review.projection} quote={review.quote}/>{error&&<p className="form-error" role="alert">{error}</p>}<div className="confirm-actions"><button className="secondary" disabled={busy} onClick={closeReview}>Cancel</button><button className="primary" disabled={busy} onClick={()=>void submit(review)}>{busy?'Submitting…':review.p_action==='buy'?'Confirm buy':'Confirm sell'}</button></div></div></Modal>}
  {warning&&<Modal title="Responsible gambling*" onClose={closeWarning}><div className="loss-warning"><span className="eyebrow">*Satire · virtual credits only</span><h3>You’ve lost ◈ {fmt(warning.loss)} in the last 24 hours.</h3><p>That’s {fmt(warning.ratio*100,1)}% of your bankroll. Are you sure you want to continue?</p><div className="confirm-actions"><button className="secondary" onClick={continueWarning}>Yes</button><button className="primary" onClick={continueWarning}>Hell yeah!</button></div></div></Modal>}
 </aside>;
}
