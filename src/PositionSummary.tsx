import {formatShares,formatDateTime} from './display-format.mjs';
import type {OutcomePreview,TradeProjection,PortfolioPosition} from './position-preview.mjs';
const fmt=(n:number)=>Number(n).toLocaleString(undefined,{maximumFractionDigits:2});
const shares=formatShares;
function Amount({value,signed=false}:{value:number|null;signed?:boolean}){return <b className={value==null?'muted':value>0?'positive':value<0?'negative':''}>{value==null?'—':`${value<0?'−':signed&&value>0?'+':''}◈ ${fmt(Math.abs(value))}`}</b>;}
export function ExistingHoldings({position,side,action,loading}:{position:Pick<PortfolioPosition,'yesShares'|'noShares'|'basisYes'|'basisNo'>;side:'yes'|'no';action:'buy'|'sell';loading:boolean}){
 const any=position.yesShares+position.noShares>0,selected=position[side==='yes'?'yesShares':'noShares'];
 if(!any)return null;
 return <section className="existing-holdings" aria-label="Already invested in this market"><h3>You already have a position</h3>{(['yes','no'] as const).filter(s=>position[s==='yes'?'yesShares':'noShares']>0).map(s=><div key={s}><span><b className={s==='yes'?'positive':'negative'}>{s==='yes'?'Yes':'No'}</b> · {formatShares(position[s==='yes'?'yesShares':'noShares'])} shares</span><small>{loading?'Updating cost…':`◈ ${fmt(position[s==='yes'?'basisYes':'basisNo'])} invested`}</small></div>)}<p>{action==='buy'?selected>0?`This purchase adds to your ${side==='yes'?'Yes':'No'} position.`:`This purchase opens a ${side==='yes'?'Yes':'No'} position alongside your existing holdings.`:`Selling reduces your ${side==='yes'?'Yes':'No'} shares.`}</p></section>;
}
export function OutcomeRows({items}:{items:{label:string;value:OutcomePreview;note?:string}[]}){return <div className="position-outcomes">{items.map(item=><section key={item.label}><h4>{item.label}</h4><dl><div><dt>Total return</dt><dd><Amount value={item.value.return}/></dd></div><div><dt>Profit / loss</dt><dd><Amount value={item.value.profit} signed/></dd></div></dl>{item.note&&<small>{item.note}</small>}</section>)}</div>;}
export function PredictionPreview({value,book,action}:{value:TradeProjection;book:boolean;action:'buy'|'sell'}){return <section className="prediction-preview" aria-label="Holdings after this trade"><div className="preview-net-position"><span>{value.change}</span><strong><span className="positive">{shares(value.yesShares)} Yes</span> · <span className="negative">{shares(value.noShares)} No</span></strong><small>Shares after this trade · purchase cost ◈ {fmt(value.basis)}</small></div>{(action==='sell'||value.reserved>0)&&<div className="immediate-returns">{action==='sell'&&<div><span>Profit realised now</span><Amount value={value.realised} signed/></div>}{value.reserved>0&&<div><span>Reserved for unmatched orders</span><Amount value={value.reserved}/></div>}</div>}<OutcomeRows items={[{label:'If Yes',value:value.yes},{label:'If No',value:value.no}]}/>{book&&<p className="projection-note">{value.failed?'Fill-all order cannot execute at these prices.':value.pending?`${shares(value.matched)} shares can match now; ${shares(value.pending)} wait. Holdings and outcomes assume full matching.`:'Based on currently available matches.'}</p>}{value.debt>0&&<p className="projection-note">Returns include repayment of ◈ {fmt(value.debt)} borrowed.</p>}</section>;}

export function TradeReview({action,side,amount,factor,price,expires,projection,quote}:{action:'buy'|'sell';side:'yes'|'no';amount:number;factor:number;price:number|null;expires:string|null;projection:TradeProjection;quote:{shares:number;total:number;mode:string;repaid:number}}){
 const buying=action==='buy',outcome=side==='yes'?'Yes':'No';
 return <>
  <div className="trade-review-heading"><strong>{buying?'Buy':'Sell'} <span className={`outcome-chip ${side}`}>{outcome}</span></strong><span>{quote.mode==='automatic'?'Instant trade':quote.mode==='market'?'Market order':'Limit order'}</span></div>
  <dl className="trade-review-facts">
   <div><dt>{buying?(factor>1?'Your credits':quote.mode==='market'?'Maximum spend':'Amount'):'Shares to sell'}</dt><dd>{buying?`◈ ${fmt(amount)}`:formatShares(amount)}</dd></div>
   {buying&&<div><dt>Estimated shares</dt><dd>{formatShares(quote.shares)} {outcome}</dd></div>}
   <div><dt>{quote.mode==='limit'?'Limit price':'Est. average price'}</dt><dd>◈ {Number(quote.mode==='limit'?price:quote.shares>0?quote.total/quote.shares:0).toLocaleString(undefined,{maximumFractionDigits:4})}</dd></div>
   {expires&&<div><dt>Expires</dt><dd>{formatDateTime(expires)}</dd></div>}
   {factor>1&&<><div><dt>Borrowed</dt><dd>◈ {fmt(amount*(factor-1))}</dd></div><div><dt>Maximum loss</dt><dd>◈ {fmt(amount*factor)}</dd></div></>}
   {quote.repaid>0&&<div><dt>Loan repayment</dt><dd>◈ {fmt(quote.repaid)}</dd></div>}
  </dl>
  <div className="trade-review-result"><span>{buying?`Payout if ${outcome} wins`:'Estimated return'}<small>{projection.pending>0?'If the full order is matched':buying?'1 credit per winning share':'After any loan repayment'}</small></span><strong>◈ {fmt(buying?quote.shares:quote.total-quote.repaid)}</strong></div>
  {projection.pending>0?<p className="trade-review-note">{formatShares(projection.matched)} shares can match now. {formatShares(projection.pending)} will wait at your limit price.</p>:quote.mode==='market'?<p className="trade-review-note">Estimated fill: {formatShares(projection.matched)} shares. Any unfilled amount is cancelled and released.</p>:null}
  {factor>1&&<p className="trade-review-warning">Payout is shown before loan repayment. Borrowing must be repaid even if you lose and can leave your balance negative.</p>}
 </>;
}
