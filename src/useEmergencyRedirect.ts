import {useEffect} from 'react';
import {supabase,supabaseUrl,supabasePublishableKey} from './db';
import {EMERGENCY_URL,recordEscape,shouldRedirectForEmergency} from './interactions.mjs';
const CURSOR='multimarche-emergency-version',LOCAL_SIGNAL='multimarche-emergency-local';
type Signal={version:number;triggered_at:string|null};
export default function useEmergencyRedirect(hide:()=>void){
 useEffect(()=>{
  let active=true,navigating=false,triggering=false,accessToken='',taps:number[]=[],redirectTimer:ReturnType<typeof setTimeout>|undefined;
  let lastSeen:number|null=null;
  try{const stored=localStorage.getItem(CURSOR);if(stored!==null&&Number.isSafeInteger(Number(stored)))lastSeen=Number(stored);}catch{}
  const remember=(version:number)=>{lastSeen=version;try{localStorage.setItem(CURSOR,String(version));}catch{}};
  const tellLocalTabs=()=>{try{localStorage.setItem(LOCAL_SIGNAL,`${Date.now()}:${Math.random()}`);}catch{}};
  const go=(version?:number)=>{if(navigating)return;navigating=true;if(redirectTimer)clearTimeout(redirectTimer);if(version!==undefined)remember(version);hide();window.location.replace(EMERGENCY_URL);};
  const accept=(signal:Signal)=>{
   if(!active||!Number.isSafeInteger(Number(signal.version)))return;
   if(shouldRedirectForEmergency(signal,lastSeen)){remember(Number(signal.version));tellLocalTabs();go();}
   else if(lastSeen===null)remember(Number(signal.version));
  };
  const poll=async()=>{try{const response=await fetch(`${supabaseUrl}/rest/v1/emergency_signal?select=version,triggered_at&id=eq.1`,{headers:{apikey:supabasePublishableKey},cache:'no-store',signal:AbortSignal.timeout(8000)});if(response.ok){const rows=await response.json();if(rows[0])accept(rows[0]);}}catch{}};
  void supabase.auth.getSession().then(({data})=>{if(active)accessToken=data.session?.access_token??'';});
  const auth=supabase.auth.onAuthStateChange((_event,session)=>{accessToken=session?.access_token??'';});
  const channel=supabase.channel('emergency-redirect').on('postgres_changes',{event:'UPDATE',schema:'public',table:'emergency_signal'},payload=>accept(payload.new as Signal)).subscribe(status=>{if(status==='SUBSCRIBED')void poll();});
  void poll();
  const interval=setInterval(()=>{if(document.visibilityState==='visible')void poll();},10000);
  const focus=()=>void poll();
  const visible=()=>{if(document.visibilityState==='visible')void poll();};
  const storage=(event:StorageEvent)=>{if(event.key===LOCAL_SIGNAL&&event.newValue)go();};
  const key=(event:KeyboardEvent)=>{
   if(event.key!=='Escape'||event.repeat||navigating||triggering)return;
   taps=recordEscape(taps,Date.now());if(taps.length<3)return;
   event.preventDefault();event.stopImmediatePropagation();triggering=true;hide();tellLocalTabs();
   if(!accessToken){go();return;}
   // keepalive lets the authenticated broadcast finish if navigation starts first.
   redirectTimer=setTimeout(()=>go(),900);
   void fetch(`${supabaseUrl}/rest/v1/rpc/trigger_emergency`,{method:'POST',headers:{apikey:supabasePublishableKey,authorization:`Bearer ${accessToken}`,'content-type':'application/json'},body:'{}',keepalive:true}).then(async response=>{
    if(response.ok){const version=Number(await response.json());if(Number.isSafeInteger(version))remember(version);}
    go();
   }).catch(()=>go());
  };
  window.addEventListener('keydown',key,true);window.addEventListener('storage',storage);window.addEventListener('focus',focus);document.addEventListener('visibilitychange',visible);
  return()=>{active=false;clearInterval(interval);if(redirectTimer)clearTimeout(redirectTimer);auth.data.subscription.unsubscribe();void supabase.removeChannel(channel);window.removeEventListener('keydown',key,true);window.removeEventListener('storage',storage);window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',visible);};
 },[hide]);
}
