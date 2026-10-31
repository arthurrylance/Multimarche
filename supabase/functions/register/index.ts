import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
Deno.serve(async (req:Request) => {
  if (req.method==='OPTIONS') return new Response('ok',{headers:cors});
  const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
  if(req.method!=='POST') return reply(405,{error:'Method not allowed'});
  try {
    if(Number(req.headers.get('content-length')||0)>4096)return reply(413,{error:'Request too large'});
    const {username,password,invite}=await req.json();
    if(typeof username!=='string'||!/^[a-z0-9_]{3,24}$/.test(username)||typeof password!=='string'||password.length<10||password.length>128||typeof invite!=='string'||invite.length>200) return reply(400,{error:'Use a 3–24 character username and a password of 10–128 characters.'});
    // This public registration endpoint authenticates membership using a secret invitation.
    // The auth trigger atomically validates/consumes the invitation before creating a profile.
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const {error}=await admin.auth.admin.createUser({email:`${username}@members.multimarche.invalid`,password,email_confirm:true,user_metadata:{username,invite}});
    if(error) return reply(400,{error:'Registration failed. Check your invite code or try another username.'});
    return reply(200,{ok:true});
  } catch {return reply(400,{error:'Invalid registration request'});}
});
