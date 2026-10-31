// Optional live integration test for an isolated staging project. Feed {"invite":"<temporary code>"} on stdin.
// Creates two fixture users and a market. The printed fixture IDs must be cleaned up by an owner.
import {createClient} from '@supabase/supabase-js';
import {randomBytes,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const input=await new Promise(resolve=>{process.stdin.once('data',d=>resolve(JSON.parse(d.toString())));});
const url=process.env.TEST_SUPABASE_URL,key=process.env.TEST_SUPABASE_KEY;
assert.ok(url&&key,'Set isolated staging TEST_SUPABASE_URL and TEST_SUPABASE_KEY; this test creates persistent fixtures.');
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
 assert.equal(m.execution_model,'clob');assert.equal(m.price_available,false);
 const args={p_market:mid,p_side:'yes',p_action:'buy',p_price:.6,p_quantity:50,p_tif:'GTC',p_expires:null,p_request:randomUUID()};
 const order=check(await a.rpc('place_order',args));assert.equal(order.status,'open');
 check(await a.rpc('place_order',args));
 assert.equal(Number(check(await a.from('wallets').select('reserved_balance').single()).reserved_balance),30);
 assert.equal(check(await a.from('positions').select('*').eq('market_id',mid)).length,0,'Unfilled buys create no shares');
 check(await b.rpc('place_order',{...args,p_side:'no',p_price:.4,p_tif:'FOK',p_request:randomUUID()}));
 assert.equal(Number(check(await a.from('positions').select('shares').eq('market_id',mid).single()).shares),50);
 const concurrent=await Promise.all([1,2].map(()=>a.rpc('place_order',{...args,p_price:.1,p_quantity:8000,p_request:randomUUID()})));
 assert.equal(concurrent.filter(r=>!r.error).length,1,'Only one concurrent large reservation can use the wallet');
 check(await a.rpc('cancel_my_orders',{p_market:mid}));
 assert.equal(Number(check(await a.from('wallets').select('reserved_balance').single()).reserved_balance),0);
 const before=check(await b.from('wallets').select('balance,reserved_balance').single());
 assert.ok((await b.rpc('place_order',{...args,p_side:'no',p_price:.1,p_quantity:1000,p_tif:'FOK',p_request:randomUUID()})).error,'FOK must fail without sufficient liquidity');
 assert.deepEqual(check(await b.from('wallets').select('balance,reserved_balance').single()),before);
 check(await a.rpc('place_order',{...args,p_action:'sell',p_price:.7,p_quantity:25,p_request:randomUUID()}));
 check(await b.rpc('place_order',{...args,p_price:.75,p_quantity:25,p_tif:'FOK',p_request:randomUUID()}));
 assert.equal(Number(check(await a.from('positions').select('shares').eq('market_id',mid).single()).shares),25);
 assert.equal(check(await b.from('wallets').select('user_id')).length,1,'RLS must hide other wallets');
 assert.ok(check(await b.from('positions').select('*')).every(p=>p.user_id===fixtures.users[1]),'RLS must hide other positions');
 assert.ok(check(await b.from('orders').select('*')).every(o=>o.user_id===fixtures.users[1]),'RLS must hide other individual orders');
 check(await b.from('watchlist').insert({user_id:fixtures.users[1],market_id:mid}));
 check(await b.from('comments').insert({user_id:fixtures.users[1],market_id:mid,body:'Live integration test comment.'}));
 check(await a.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'First independent live test observation.'}));
 assert.ok((await a.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'Same person cannot confirm twice.'})).error);
 check(await b.rpc('resolve_market',{p_market:mid,p_outcome:'yes',p_evidence:'Second independent live test observation.'}));
 const payments=check(await a.from('ledger').select('amount').eq('market_id',mid).eq('reason','Settlement: yes'));
 assert.equal(payments.length,1);assert.equal(Number(payments[0].amount),25);
 assert.equal(Number(check(await a.from('wallets').select('balance').single()).balance),1012.5);
 assert.equal(Number(check(await b.from('wallets').select('balance').single()).balance),987.5);
 assert.equal(check(await a.from('markets').select('status').eq('id',mid).single()).status,'resolved');
 await new Promise(resolve=>setTimeout(resolve,1200));assert.ok(received,'Second client must receive Realtime updates');
 assert.ok((await anonymous.from('markets').select('*')).error,'Anonymous queries must be denied');
 console.log('PASS: real invitation signup, username/password login, starting credits, two-client Realtime, matched complementary/direct orders, idempotency, concurrent reservations, FOK rollback, cancellation, sell, wallet/position/order RLS, comments, watchlist, two-person settlement and payout.');
}finally{
 if(channel)await clients[1].removeChannel(channel);
 await Promise.all(clients.map(c=>c.auth.signOut()));
 console.log('CLEANUP',JSON.stringify(fixtures));
}
