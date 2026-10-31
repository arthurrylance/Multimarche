import {useEffect,useRef,useState} from 'react';
import {supabase} from './db';
import type {Profile} from './types';
export default function PresenceAvatars({userId,profiles}:{userId:string;profiles:Profile[]}){
 const[online,setOnline]=useState<string[]>([]),tabId=useRef(crypto.randomUUID());
 useEffect(()=>{
  let active=true;
  const load=async()=>{const{data,error}=await supabase.rpc('online_members');if(active&&!error)setOnline(data??[]);};
  const ping=async()=>{const visible=document.visibilityState==='visible';const{error}=await supabase.rpc('presence_ping',{p_tab:tabId.current,p_online:visible});if(!error)void load();};
  const channel=supabase.channel(`member-presence-${userId}`).on('postgres_changes',{event:'*',schema:'public',table:'member_presence'},()=>void load()).subscribe(status=>{if(status==='SUBSCRIBED')void ping();});
  void ping();const heartbeat=setInterval(()=>void ping(),20000),expiry=setInterval(()=>void load(),10000);
  const visibility=()=>void ping();document.addEventListener('visibilitychange',visibility);window.addEventListener('online',visibility);
  return()=>{active=false;clearInterval(heartbeat);clearInterval(expiry);document.removeEventListener('visibilitychange',visibility);window.removeEventListener('online',visibility);void supabase.rpc('presence_ping',{p_tab:tabId.current,p_online:false});void supabase.removeChannel(channel);};
 },[userId]);
 const members=profiles.filter(p=>p.active!==false&&online.includes(p.id));
 return <div className="presence-avatars" title="Active on Multimarché within the last minute" aria-label={`${members.length} online`}><div className="presence-stack">{members.slice(0,5).map(p=>{const name=p.nickname||p.username,initials=name.trim().split(/\s+/).map(n=>n[0]).slice(0,2).join('').toUpperCase()||'?';return <span tabIndex={0} className="presence-avatar" key={p.id} aria-label={`${name}${p.id===userId?' (you)':''} is online`}><b>{initials}</b><span className="presence-tooltip">{name}{p.id===userId?' (you)':''}</span></span>;})}{members.length>5&&<span className="presence-avatar">+{members.length-5}</span>}</div><small>{members.length} online</small></div>;
}
