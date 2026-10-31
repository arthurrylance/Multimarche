import {useState} from 'react';
import type {FormEvent} from 'react';
import {LogOut,Save} from 'lucide-react';
import Avatar from './Avatar';
import {supabase} from './db';
import type {Profile} from './types';
export default function AccountPage({profile,refresh,notify}:{profile:Profile;refresh:()=>void;notify:(s:string)=>void}){
 const[username,setUsername]=useState(profile.username),[nickname,setNickname]=useState(profile.nickname??''),[current,setCurrent]=useState(''),[password,setPassword]=useState(''),[confirm,setConfirm]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const submit=async(e:FormEvent)=>{e.preventDefault();setBusy(true);setError('');try{
  if(password!==confirm)throw new Error('New passwords do not match.');
  const{data,error}=await supabase.functions.invoke('account',{body:{username:username.trim().toLowerCase(),nickname,currentPassword:current,...(password?{newPassword:password}:{})}});
  if(error){let message='Could not update your account.';try{message=(await error.context.json()).error??message;}catch{}throw new Error(message);}
  if(data?.error)throw new Error(data.error);
  await supabase.auth.refreshSession();setCurrent('');setPassword('');setConfirm('');refresh();notify('Profile saved.');
 }catch(e){setError(e instanceof Error?e.message:'Could not save changes.');}finally{setBusy(false);}};
 return <><div className="page-heading compact"><h1>Account</h1><button className="secondary" onClick={async()=>{const{error}=await supabase.auth.signOut();if(error)notify(error.message);}}><LogOut size={16}/>Log out</button></div><form className="settings-card" onSubmit={submit}><div className="account-picture"><Avatar userId={profile.id} size={64}/><h2>Profile</h2></div><label>Nickname<input maxLength={40} value={nickname} onChange={e=>setNickname(e.target.value)} placeholder="Optional display name" autoComplete="nickname"/><small>Shown to the group. Your username is used to log in.</small></label><label>Username<input required pattern="[a-z0-9_]{3,24}" minLength={3} maxLength={24} value={username} onChange={e=>setUsername(e.target.value.toLowerCase())} autoComplete="username"/></label><h2>Password</h2><label>Current password<input type="password" autoComplete="current-password" value={current} onChange={e=>setCurrent(e.target.value)} required={username!==profile.username||!!password}/><small>Required to change your username or password.</small></label><label>New password<input type="password" minLength={10} maxLength={128} autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)}/></label><label>Confirm new password<input type="password" autoComplete="new-password" value={confirm} onChange={e=>setConfirm(e.target.value)}/></label>{error&&<p className="form-error" role="alert">{error}</p>}<button className="primary" disabled={busy}><Save size={16}/>{busy?'Saving…':'Save changes'}</button></form></>;
}
