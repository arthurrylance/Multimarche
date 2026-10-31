import {useRef,useState} from 'react';
import type {FormEvent} from 'react';
import {supabase} from './db';
export default function AdminMoneyReset({disabled,onBusyChange,refresh,notify}:{disabled:boolean;onBusyChange:(busy:boolean)=>void;refresh:()=>void;notify:(s:string)=>void}){
 const[confirmation,setConfirmation]=useState(''),[acknowledged,setAcknowledged]=useState(false),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[completed,setCompleted]=useState(false);
 const flight=useRef(false),request=useRef<{reason:string;id:string}|null>(null);
 const reset=async(e:FormEvent)=>{
  e.preventDefault();if(flight.current||disabled||confirmation!=='RESET ALL'||!acknowledged)return;
  const note=reason.trim()||'Fresh start';if(request.current?.reason!==note)request.current={reason:note,id:crypto.randomUUID()};
  flight.current=true;setBusy(true);onBusyChange(true);setError('');
  try{const{error}=await supabase.rpc('admin_reset_economy',{p_confirmation:confirmation,p_reason:note,p_request:request.current.id});if(error)throw error;request.current=null;setConfirmation('');setAcknowledged(false);setCompleted(true);refresh();notify('Money reset. Active accounts now have ◈ 1,000.');}catch(e){setError((e as {message?:string}).message||'Could not reset money.');}finally{flight.current=false;setBusy(false);onBusyChange(false);}
 };
 return <details className="money-reset"><summary>Reset all money</summary><form onSubmit={reset}>
  <p>Void open markets, cancel pending orders and archive existing markets. Active accounts start again with <b>◈ 1,000</b>; removed accounts are cleared. Accounts and transaction history stay.</p>
  <p>Remaining credits return to treasury. Total issued credits stay unchanged.</p>
  <label>Reason (optional)<input value={reason} onChange={e=>{setReason(e.target.value);setCompleted(false);}} placeholder="e.g. Testing finished"/></label>
  <label className="checkbox-label"><input type="checkbox" checked={acknowledged} onChange={e=>setAcknowledged(e.target.checked)}/>I understand open markets will close and balances will reset.</label>
  <label>Type RESET ALL to confirm<input aria-label="Reset confirmation" value={confirmation} autoComplete="off" spellCheck={false} onChange={e=>setConfirmation(e.target.value)}/></label>
  {error&&<p className="form-error" role="alert">{error}</p>}{completed&&<p role="status">Reset complete.</p>}
  <button className="reset-money-button" disabled={disabled||busy||confirmation!=='RESET ALL'||!acknowledged}>{busy?'Resetting…':'Reset balances & close markets'}</button>
 </form></details>;
}
