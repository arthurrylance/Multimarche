import {useCallback,useRef,useState} from 'react';
import type {FormEvent} from 'react';
import {Users,ShieldCheck} from 'lucide-react';
import {supabase} from './db';
import Modal from './Modal';
import type {Market,Vote} from './types';
export default function ResolutionPanel({market:m,votes,userId,admin,frozen,name,refresh,notify}:{market:Market;votes:Vote[];userId:string;admin:boolean;frozen:boolean;name:(id:string)=>string;refresh:()=>void;notify:(s:string)=>void}){
 const[dialog,setDialog]=useState<'vote'|'admin'|null>(null),[outcome,setOutcome]=useState('yes'),[evidence,setEvidence]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const flight=useRef(false),close=useCallback(()=>setDialog(null),[]),mine=votes.find(v=>v.user_id===userId);
 const counts={yes:votes.filter(v=>v.outcome==='yes').length,no:votes.filter(v=>v.outcome==='no').length,void:votes.filter(v=>v.outcome==='void').length};
 const disputed=m.resolution_disputed||Object.values(counts).filter(n=>n>0).length>1;
 const requiredVotes=m.required_verifications??2;
 const adminRequired=m.volume>2000;
 const awaitingAdmin=adminRequired&&!disputed&&m.status==='proposed'&&m.outcome!==null&&counts[m.outcome]>=requiredVotes;
 const open=(next:string,kind:'vote'|'admin'='vote')=>{setOutcome(next);setEvidence('');setError('');setDialog(kind);};
 const submit=async(e:FormEvent)=>{
  e.preventDefault();if(flight.current||frozen)return;flight.current=true;setBusy(true);setError('');
  try{
   const{data,error}=dialog==='admin'?await supabase.rpc('admin_market',{p_market:m.id,p_action:'settle',p_data:{outcome},p_reason:evidence||`Admin confirmed ${outcome}`}):await supabase.rpc('resolve_market',{p_market:m.id,p_outcome:outcome,p_evidence:evidence});
   if(error)throw error;setDialog(null);refresh();notify(dialog==='admin'||data==='resolved'?'Market resolved.':data==='disputed'?'Disagreement recorded. Result is disputed.':'Your vote was recorded.');
  }catch(e){setError((e as {message?:string}).message||'Could not record result.');}finally{flight.current=false;setBusy(false);}
 };
 const withdraw=async()=>{
  if(flight.current||frozen)return;flight.current=true;setBusy(true);setError('');
  try{const{error}=await supabase.rpc('withdraw_resolution',{p_market:m.id});if(error)throw error;refresh();notify('Your vote was withdrawn.');}catch(e){setError((e as {message?:string}).message||'Could not withdraw vote.');}finally{flight.current=false;setBusy(false);}
 };
 if(m.status==='resolved')return null;
 return <><section className="resolution-box"><div className="resolution-icon"><Users size={22}/></div><div>
  <h3>{disputed?'Result disputed':awaitingAdmin?'Awaiting admin confirmation':m.status==='proposed'?'Confirm or disagree':'Resolve market'}</h3>
  <p>{disputed?'Trading and payouts stay paused while votes disagree. Change or withdraw your vote, or ask an admin to resolve.':m.status==='proposed'?`${m.outcome?.toUpperCase()} proposed. ${counts[m.outcome as keyof typeof counts]??0}/${requiredVotes} agree. You can choose a different result.`:`${requiredVotes} different accounts must agree, with no opposing votes.`}</p>
  {adminRequired&&<p>Markets with more than 2,000 credits in trading volume require admin confirmation before payouts.</p>}
  {votes.length>0&&<div className="resolution-counts"><span className="positive">Yes {counts.yes}</span><span className="negative">No {counts.no}</span><span>Void {counts.void}</span></div>}
  {votes.map(v=><blockquote key={v.user_id}><b>{name(v.user_id)} · {v.outcome.toUpperCase()}</b>{v.evidence&&<p>{v.evidence}</p>}</blockquote>)}
  <div className="resolution-actions">{mine?<><button className="secondary" disabled={busy||frozen} onClick={()=>open(mine.outcome)}>Change my vote</button><button className="text-button" disabled={busy||frozen} onClick={()=>void withdraw()}>Withdraw my vote</button></>:<><button className="secondary yes-button" disabled={busy||frozen} onClick={()=>open('yes')}>Yes, it happened</button><button className="secondary no-button" disabled={busy||frozen} onClick={()=>open('no')}>No, it didn’t</button><button className="secondary" disabled={busy||frozen} onClick={()=>open('void')}>Void / unclear</button></>}
  {admin&&<button className="secondary admin-resolve-button" disabled={busy||frozen} onClick={()=>open(m.outcome??'yes','admin')}>{awaitingAdmin?'Confirm result as admin':'Resolve as admin'}</button>}</div>
  {error&&!dialog&&<p className="form-error" role="alert">{error}</p>}
 </div></section>{dialog&&<Modal title={dialog==='admin'?'Resolve as admin':mine?'Change your vote':'Vote on result'} onClose={close}><form onSubmit={submit}>
  <p className="modal-intro">{dialog==='admin'?'Resolve and pay out immediately. This override is recorded.':`${requiredVotes} accounts must agree. Opposing votes pause settlement until the disagreement is cleared. Proposing a result stops trading.`}</p>
  <label>Outcome<select value={outcome} onChange={e=>setOutcome(e.target.value)}><option value="yes">Yes — it happened</option><option value="no">No — it didn’t</option><option value="void">Void — unclear</option></select></label>
  <label>Note (optional)<textarea rows={3} placeholder="What did you observe?" value={evidence} onChange={e=>setEvidence(e.target.value)}/></label>
  {error&&<p className="form-error" role="alert">{error}</p>}<button className="primary full" disabled={busy||frozen}>{busy?'Submitting…':dialog==='admin'?'Resolve & pay out':'Submit my vote'}<ShieldCheck size={17}/></button>
 </form></Modal>}</>;
}
