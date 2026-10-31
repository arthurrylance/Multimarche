export function requiresTradeConfirmation(cost,balance){return cost>0&&(cost>=100||(balance>0&&cost>=balance*.25));}
export function recordEscape(previous,now){return [...previous.filter(t=>now-t<=1500),now];}
export const EMERGENCY_URL='https://nordangliaeducation.itslearning.com/CourseCards';
export function shouldRedirectForEmergency(signal,lastSeen,now=Date.now()){
 const version=Number(signal?.version);if(!Number.isSafeInteger(version)||version<=0)return false;
 if(lastSeen!==null)return version>lastSeen;
 const age=now-Date.parse(signal.triggered_at);return Number.isFinite(age)&&age>=-60000&&age<=120000;
}
export function marketNotifications(markets,votes,userId,now=Date.now()){
 return markets.filter(m=>!m.archived&&!m.history_deleted_at&&(m.status==='resolved'||m.status==='proposed'||Date.parse(m.closes_at)<=now)).map(m=>{
  const matching=votes.filter(v=>v.market_id===m.id&&v.outcome===m.outcome);
  const kind=m.status==='resolved'?'resolved':m.status==='proposed'?'proposed':'ended';
  const timestamp=kind==='resolved'?m.resolved_at:kind==='proposed'?m.state_changed_at:m.closes_at;
  return {key:`${m.id}:${kind}:${timestamp}`,kind,market:m,count:matching.length,required:m.required_verifications??2,hasVoted:matching.some(v=>v.user_id===userId),timestamp:timestamp??m.closes_at};
 }).sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp));
}
