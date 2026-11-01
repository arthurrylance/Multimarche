-- All fixtures, trades, loan draws and reset calls are rolled back. Never commit this file.
begin;
insert into private.invites values(encode(extensions.digest('games-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000a01','games_admin@members.multimarche.invalid','{"username":"games_admin","invite":"games-test-only"}'),
('00000000-0000-4000-8000-000000000a02','games_a@members.multimarche.invalid','{"username":"games_a","invite":"games-test-only"}'),
('00000000-0000-4000-8000-000000000a03','games_b@members.multimarche.invalid','{"username":"games_b","invite":"games-test-only"}'),
('00000000-0000-4000-8000-000000000a04','games_c@members.multimarche.invalid','{"username":"games_c","invite":"games-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000a01');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
-- Public blackjack starts hide the deck and the dealer hole card; replays charge once.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select set_config('test.request',gen_random_uuid()::text,true);
select set_config('test.hand',(public.casino_start('blackjack',2,null,current_setting('test.request')::uuid)->>'id'),true);
select public.casino_start('blackjack',2,null,current_setting('test.request')::uuid);
do $$declare r public.casino_rounds;begin
 select * into r from public.casino_rounds where id=current_setting('test.hand')::uuid;
 if (select count(*) from public.casino_rounds)<>1 then raise exception 'Start replay duplicated round';end if;
 if r.status='active' and (r.state->'dealer'->1<>'null'::jsonb or r.state->'dealer_total'<>'null'::jsonb) then raise exception 'Dealer hole card leaked';end if;
 if (public.casino_state()->>'remaining')::numeric<>98 then raise exception 'Replay changed daily budget';end if;
 begin perform * from private.casino_hands;raise exception 'TEST FAILED private deck readable';exception when insufficient_privilege then null;end;
 begin update public.casino_rounds set payout=1000 where id=r.id;raise exception 'TEST FAILED round writable';exception when insufficient_privilege then null;end;
 begin perform public.casino_start('plinko',6,null,gen_random_uuid());raise exception 'TEST FAILED large stake';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
-- Deterministic fixture checks Ace scoring, Hit/Stand, hidden hole card, ownership and version guards.
reset role;
do $$declare rid uuid;deck integer[];begin
 if private.blackjack_score(array[0,1,36])<>12 or private.blackjack_score(array[0,20])<>17 or private.blackjack_score(array[36,40,4])<>22 then raise exception 'Ace or face-card scoring wrong';end if;
 select array[0,36,20,24,4]||array_agg(n order by n) into deck from generate_series(0,51) n where n<>all(array[0,36,20,24,4]);
 insert into public.casino_rounds(user_id,game,stake,max_payout,economy_round) values('00000000-0000-4000-8000-000000000a03','blackjack',2,5,(select reset_version from private.economy)) returning id into rid;
 update public.wallets set balance=balance-2 where user_id='00000000-0000-4000-8000-000000000a03';insert into public.ledger(user_id,amount,reason) values('00000000-0000-4000-8000-000000000a03',-2,'Games: blackjack stake');
 insert into private.credit_accounts values('casino:'||rid,0);perform private.transfer('treasury','casino:'||rid,5,'Games payout reserve',null);
 insert into private.casino_hands values(rid,deck,array[0,20],array[36,24],5);update public.casino_rounds set state=private.blackjack_view(rid,false) where id=rid;
 perform set_config('test.forced',rid::text,true);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
do $$begin begin perform public.casino_blackjack(current_setting('test.forced')::uuid,'hit',1,gen_random_uuid());raise exception 'TEST FAILED other player hand';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select set_config('test.hit',gen_random_uuid()::text,true);
select public.casino_blackjack(current_setting('test.forced')::uuid,'hit',1,current_setting('test.hit')::uuid);
select public.casino_blackjack(current_setting('test.forced')::uuid,'hit',1,current_setting('test.hit')::uuid);
do $$declare r public.casino_rounds;begin
 select * into r from public.casino_rounds where id=current_setting('test.forced')::uuid;
 if r.state->>'player_total'<>'19' or jsonb_array_length(r.state->'player')<>3 or r.state->'dealer'->1<>'null'::jsonb then raise exception 'Hit/replay/hidden hole failed';end if;
 begin perform public.casino_blackjack(r.id,'hit',1,gen_random_uuid());raise exception 'TEST FAILED stale action version';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select public.casino_blackjack(current_setting('test.forced')::uuid,'stand',2,gen_random_uuid());
do $$begin if (select payout from public.casino_rounds where id=current_setting('test.forced')::uuid)<>4 or (select balance from public.wallets)<>1002 then raise exception 'Stand on soft 17 or 1:1 win failed';end if;end $$;
-- Roulette outcomes and plinko paths/payouts are internally consistent and repeat-safe.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
do $$declare r jsonb;req uuid;n integer;choice text;won boolean;i integer;path_total integer;begin
 for i in 1..40 loop
  choice:=(array['red','black','odd','even'])[1+(i%4)];req:=gen_random_uuid();r:=public.casino_start('roulette',1,choice,req);n:=(r->'state'->>'number')::integer;
  if n not between 0 and 36 then raise exception 'Roulette number out of range';end if;
  won:=n<>0 and case choice when 'red' then n=any(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]) when 'black' then n<>all(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]) when 'odd' then n%2=1 else n%2=0 end;
  if (r->>'payout')::numeric<>(case when won then 2 else 0 end) then raise exception 'Roulette payout wrong';end if;
  if public.casino_start('roulette',1,choice,req)->>'id'<>r->>'id' then raise exception 'Roulette replay changed outcome';end if;
 end loop;
 for i in 1..60 loop
  r:=public.casino_start('plinko',1,null,gen_random_uuid());select sum(value::integer) into path_total from jsonb_array_elements_text(r->'state'->'path');
  if jsonb_array_length(r->'state'->'path')<>8 or path_total<>(r->'state'->>'slot')::integer or (r->>'payout')::numeric<>(array[8,3,1.5,.7,.4,.7,1.5,3,8]::numeric[])[path_total+1] then raise exception 'Plinko path or payout wrong';end if;
 end loop;
 begin perform public.casino_start('plinko',1,null,gen_random_uuid());raise exception 'TEST FAILED daily budget bypass';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if (public.casino_state()->>'remaining')::numeric<>0 then raise exception 'Daily budget remaining wrong';end if;
end $$;
reset role;
set constraints all immediate;
set constraints all deferred;
-- Unfunded treasury rolls back the entire start, including the stake debit.
do $$declare old_balance numeric;old_count bigint;before_cash numeric;begin
 select balance into old_balance from private.credit_accounts where id='treasury';select count(*) into old_count from public.casino_rounds;select balance into before_cash from public.wallets where user_id='00000000-0000-4000-8000-000000000a03';
 update private.credit_accounts set balance=0 where id='treasury';perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
 begin perform public.casino_start('plinko',5,null,gen_random_uuid());raise exception 'TEST FAILED unfunded payout reserve';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 update private.credit_accounts set balance=old_balance where id='treasury';
 if (select count(*) from public.casino_rounds)<>old_count or (select balance from public.wallets where user_id='00000000-0000-4000-8000-000000000a03')<>before_cash then raise exception 'Failed reserve left partial game';end if;
end $$;
-- A deterministic unfinished hand must receive its stake back on reset.
do $$declare rid uuid;deck integer[];begin
 select array[0,36,20,24,4]||array_agg(n order by n) into deck from generate_series(0,51) n where n<>all(array[0,36,20,24,4]);
 insert into public.casino_rounds(user_id,game,stake,max_payout,economy_round) values('00000000-0000-4000-8000-000000000a01','blackjack',5,12.5,(select reset_version from private.economy)) returning id into rid;
 update public.wallets set balance=balance-5 where user_id='00000000-0000-4000-8000-000000000a01';insert into public.ledger(user_id,amount,reason) values('00000000-0000-4000-8000-000000000a01',-5,'Games: blackjack stake');
 insert into private.credit_accounts values('casino:'||rid,0);perform private.transfer('treasury','casino:'||rid,12.5,'Games payout reserve',null);
 insert into private.casino_hands values(rid,deck,array[0,20],array[36,24],5);update public.casino_rounds set state=private.blackjack_view(rid,false) where id=rid;perform set_config('test.refund',rid::text,true);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_reset_economy('RESET ALL','Games reset rollback only',gen_random_uuid());
do $$begin if (select payout from public.casino_rounds where id=current_setting('test.refund')::uuid)<>5 or (select status from public.casino_rounds where id=current_setting('test.refund')::uuid)<>'void' then raise exception 'Unfinished hand was not refunded';end if;end $$;
reset role;
do $$begin if exists(select 1 from public.casino_rounds where status='active') or exists(select 1 from private.credit_accounts where id like 'casino:%' and balance<>0) or (select sum(balance) from private.credit_accounts)<>(select total_supply from private.economy) then raise exception 'Reset or conservation failed';end if;end $$;
set local role anon;
do $$begin begin perform public.casino_start('roulette',1,'red',gen_random_uuid());raise exception 'TEST FAILED guest play';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
select 'PASS: private blackjack/deck, Ace/stand scoring, replay/version/ownership guards, roulette and plinko outcomes, daily budget, funded payouts, reset and conservation' result;
rollback;
