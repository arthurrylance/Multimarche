import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
Deno.serve(async(req:Request)=>{
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
 if(req.method==='OPTIONS')return reply(200,{ok:true});
 if(req.method!=='POST')return reply(405,{error:'Method not allowed'});
 try{
  const token=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'');if(!token)return reply(401,{error:'Sign in first'});
  const url=Deno.env.get('SUPABASE_URL')!;
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const{data:{user},error:authError}=await admin.auth.getUser(token);if(authError||!user)return reply(401,{error:'Session expired'});
  const raw=await req.text();if(raw.length>1024)return reply(413,{error:'Request too large'});
  const{userId}=JSON.parse(raw);if(typeof userId!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId))return reply(400,{error:'Choose a member'});
  const caller=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:`Bearer ${token}`}}});
  // The transactional RPC rechecks admin privileges, blocks self-deletion and
  // revokes membership first, so even an unexpired target JWT loses all game access.
  const{error}=await caller.rpc('admin_delete_member',{p_user:userId});if(error)return reply(403,{error:error.message});
  const{data:target,error:lookupError}=await admin.auth.admin.getUserById(userId);
  if(lookupError&&lookupError.status!==404)return reply(502,{error:'Group access removed. Login lookup failed; retry from Removed users.'});
  if(!lookupError&&!target.user.deleted_at){
   const{error:deleteError}=await admin.auth.admin.deleteUser(userId,true);
   if(deleteError)return reply(502,{error:'Group access removed. Login cleanup failed; retry from Removed users.'});
  }
  const{error:recordError}=await admin.from('profiles').update({auth_deleted_at:new Date().toISOString()}).eq('id',userId).eq('active',false);
  if(recordError)return reply(502,{error:'Login removed. Could not save cleanup status; refresh or retry.'});
  return reply(200,{ok:true});
 }catch{return reply(400,{error:'Invalid deletion request'});}
});
