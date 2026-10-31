import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
Deno.serve(async(req:Request)=>{
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
 if(req.method==='OPTIONS')return reply(200,{ok:true});
 if(req.method!=='POST')return reply(405,{error:'Method not allowed'});
 try{
  const token=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
  if(!token)return reply(401,{error:'Sign in first'});
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:authError}=await admin.auth.getUser(token);
  if(authError||!user)return reply(401,{error:'Session expired. Sign in again.'});
  const {data:profile}=await admin.from('profiles').select('username,active').eq('id',user.id).single();
  if(!profile?.active)return reply(403,{error:'Member access required'});
  const raw=await req.text();if(raw.length>4096)return reply(413,{error:'Request too large'});
  const {username,nickname,currentPassword,newPassword}=JSON.parse(raw);
  if(typeof username!=='string'||!/^[a-z0-9_]{3,24}$/.test(username)||typeof nickname!=='string'||nickname.trim().length>40)return reply(400,{error:'Invalid username or nickname'});
  if(newPassword!==undefined&&(typeof newPassword!=='string'||newPassword.length<10||newPassword.length>128))return reply(400,{error:'Password must be 10–128 characters'});
  if(username!==profile.username||newPassword){
   if(typeof currentPassword!=='string'||currentPassword.length>128)return reply(400,{error:'Current password is required'});
   const check=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data,error}=await check.auth.signInWithPassword({email:user.email!,password:currentPassword});
   if(error||data.user?.id!==user.id)return reply(403,{error:'Current password is incorrect'});
   await check.auth.signOut({scope:'local'});
  }
  const attributes:Record<string,unknown>={user_metadata:{username,nickname:nickname.trim()}};
  if(username!==profile.username){attributes.email=`${username}@members.multimarche.invalid`;attributes.email_confirm=true;}
  if(newPassword)attributes.password=newPassword;
  // Supabase Auth updates the identity; the database trigger updates the profile
  // within that same Auth transaction, including username uniqueness checks.
  const {error}=await admin.auth.admin.updateUserById(user.id,attributes);
  if(error)return reply(400,{error:'Could not save changes. The username may already be taken.'});
  return reply(200,{ok:true,username,nickname:nickname.trim()});
 }catch{return reply(400,{error:'Invalid account update'});}
});
