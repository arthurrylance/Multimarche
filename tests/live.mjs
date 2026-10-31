// Optional live integration test. Feed {"invite":"<temporary code>"} on stdin.
// Creates two fixture users and a market. The printed fixture IDs must be cleaned up by an owner.
import {createClient} from '@supabase/supabase-js';
import {randomBytes,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {quote} from '../src/math.mjs';
const input=await new Promise(resolve=>{process.stdin.once('data',d=>resolve(JSON.parse(d.toString())));});
const url='https://vakkbgsooubqpmdekixr.supabase.co', key='sb_publishable_TaBmHyqoiGBiOEpVb0L86g_28xH5B_6';
const clients=[0,1].map(()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}));
const fixtures={users:[],markets:[]};
const check=r=>{if(r.error)throw new Error(r.error.message);return r.data;};
let channel;
try{
 const anonymous=createClient(url,key,{auth:{persistSession:false}});
 const invalid=await anonymous.functions.invoke('register',{body:{username:`bad_${randomBytes(4).toString('hex')}`,password:randomBytes(20).toString('hex'),invite:'intentionally-invalid'}});
 assert.ok(invalid.error,'Invalid invitation should fail');
 for(const client of clients){
  const username=`qatest_${randomBytes(6).toString('hex')}`, password=randomBytes(24).toString('hex');
  check(await client.functions.invoke('register',{body:{username,password,invite:input.invite}}));
  const data=check(await client.auth.signInWithPassword({email:`${username}@members.multimarche.invalid`,password}));
  fixtures.users.push(data.user.id);
  console.log('Fixture user:',data.user.id);
  assert.equal(Number(check(await client.from('wallets').select('balance').single()).balance),1000);
 }
 const [a,b]=clients;
 let received=false;
 await new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error('Realtime subscribe timed out')),15000);
  channel=b.channel('integration-'+randomUUID()).on('postgres_changes',{event:'*',schema:'public',table:'markets'},()=>{received=true;}).subscribe(s=>{if(s==='SUBSCRIBED'){clearTimeout(timeout);resolve();}else if(s==='CHANNEL_ERROR'){clearTimeout(timeout);reject(new Error('Realtime channel error'));}});
 });
 const mid=check(await a.rpc('create_market',{p_title:'QA fixture: will the live tests pass?',p_description:'Temporary automated integration fixture, removed immediately after testing.',p_category:'Other',p_emoji:'🧪',p_closes:new Date(Date.now()+3600000).toISOString()}));
 fixtures.markets.push(mid);console.log('Fixture market:',mid);
 const m=check(await a.from('markets').select('*').eq('id',mid).single());
 const request=randomUUID(), args={p_market:mid,p_side:'yes',p_action:'buy',p_shares:50,p_limit:100,p_request:request};
 const t=check(await a.rpc('trade',args));assert.ok(Math.abs(Number(t.total)-quote(m,'yes','buy',50))<1e-7);
 check(await a.rpc('trade',args));
 assert.equal(Number(check(await a.from('positions').select('shares').eq('market_id',mid).single()).shares),50);
 const concurrent=await Promise.all([1,2].map(()=>a.rpc('trade',{...args,p_shares:800,p_limit:1000,p_request:randomUUID()})));
 assert.equal(concurrent.filter(r=>!r.error).length,1,'Only one concurrent large trade can spend the wallet');
 check(await a.rpc('trade',{...args,p_action:'sell',p_shares:25,p_limit:0,p_request:randomUUID()}));
 assert.equal(check(await b.from('wallets').select('user_id')).length,1,'RLS must hide other wallets');
 assert.equal(check(await b.from('positions').select('*')).length,0,'RLS must hide other positions');
 check(await b.from('watchlist').insert({user_id:fixtures.users[1],market_id:mid}));
 check(await b.from('comments').insert({user_id:fixtures.users[1],market_id:mid,body:'Live integration test comment.'}));
 check(await a.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'First independent live test observation.'}));
 assert.ok((await a.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'Same person cannot confirm twice.'})).error);
 check(await b.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'Second independent live test observation.'}));
 const payments=check(await a.from('ledger').select('amount').eq('market_id',mid).eq('reason','Settlement: yes'));
 assert.equal(payments.length,1);assert.equal(Number(payments[0].amount),825);
 assert.equal(check(await a.from('markets').select('status').eq('id',mid).single()).status,'resolved');
 await new Promise(resolve=>setTimeout(resolve,1200));assert.ok(received,'Second client must receive Realtime updates');
 assert.ok((await anonymous.from('markets').select('*')).error,'Anonymous queries must be denied');
 console.log('PASS: real invitation signup, username/password login, starting credits, two-client Realtime, pricing parity, idempotency, concurrent spending, sell, wallet/position RLS, comments, watchlist, two-person settlement and payout.');
}finally{
 if(channel)await clients[1].removeChannel(channel);
 await Promise.all(clients.map(c=>c.auth.signOut()));
 console.log('CLEANUP',JSON.stringify(fixtures));
}
