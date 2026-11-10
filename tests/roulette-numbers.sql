-- Rollback-only fixtures: no real member, balance or setting changes persist.
begin;
set local statement_timeout='15s';
set local lock_timeout='2s';

do $$
declare choice text;n integer;expected integer;actual integer;total integer;invalid text;
begin
 for choice in select unnest(array['red','black','odd','even','green']) union all select 'number:'||i from generate_series(0,36) i loop
  total:=0;
  for n in 0..36 loop
   expected:=case when choice='green' then case when n=0 then 36 else 0 end
    when choice like 'number:%' then case when n=split_part(choice,':',2)::integer then 36 else 0 end
    when n=0 then 0
    when choice='red' then case when n=any(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]) then 2 else 0 end
    when choice='black' then case when n<>all(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]) then 2 else 0 end
    when choice='odd' then case when n%2=1 then 2 else 0 end else case when n%2=0 then 2 else 0 end end;
   actual:=private.roulette_multiplier(choice,n);total:=total+actual;
   if actual<>expected then raise exception 'TEST: wrong payout for % on %',choice,n;end if;
  end loop;
  if total<>36 then raise exception 'TEST: wrong winning distribution for %',choice;end if;
 end loop;
 foreach invalid in array array[null,'','blue','number:-1','number:37','number:00','number:3.0','number:1e1','number:99999999999999999999999'] loop
  begin perform private.roulette_multiplier(invalid,0);raise exception 'TEST: invalid bet accepted';
  exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 end loop;
end $$;

-- Temporary invited members exercise the complete funded settlement path.
do $$
declare first_uid uuid:=gen_random_uuid();second_uid uuid:=gen_random_uuid();invite text:='roulette-fixture-'||gen_random_uuid();choice text;req uuid;r jsonb;replay jsonb;cash numeric;initial_sum numeric;expected numeric;n integer;count_before bigint;invalid text;
begin
 select sum(balance) into initial_sum from private.credit_accounts;
 insert into private.invites values(encode(extensions.digest(invite,'sha256'),'hex'),2,now()+interval '1 hour');
 insert into auth.users(id,email,raw_user_meta_data) values
 (first_uid,first_uid||'@members.multimarche.invalid',jsonb_build_object('username','roulette_a_'||left(first_uid::text,8),'invite',invite)),
 (second_uid,second_uid||'@members.multimarche.invalid',jsonb_build_object('username','roulette_b_'||left(second_uid::text,8),'invite',invite));
 update private.game_settings set casino_daily_limit=100 where id=1;
 perform set_config('request.jwt.claim.sub',first_uid::text,true);
 for choice in select unnest(array['red','black','odd','even','green']) union all select 'number:'||i from generate_series(0,36) i loop
  select balance into cash from public.wallets where user_id=first_uid;
  req:=gen_random_uuid();r:=public.casino_start('roulette',1,choice,req);n:=(r->'state'->>'number')::integer;
  expected:=private.roulette_multiplier(choice,n);
  if r->>'status'<>'settled' or (r->>'payout')::numeric<>expected or r->'state'->>'choice'<>choice then raise exception 'TEST: wrong roulette settlement';end if;
  if (r->>'max_payout')::numeric<>(case when choice in('red','black','odd','even') then 2 else 36 end) then raise exception 'TEST: payout underfunded';end if;
  if (select balance from public.wallets where user_id=first_uid)<>cash-1+expected then raise exception 'TEST: wallet settlement mismatch';end if;
  replay:=public.casino_start('roulette',1,choice,req);
  if replay<>r or (select balance from public.wallets where user_id=first_uid)<>cash-1+expected then raise exception 'TEST: replay charged twice';end if;
  if exists(select 1 from private.credit_accounts where id='casino:'||(r->>'id') and balance<>0) then raise exception 'TEST: reserve not released';end if;
 end loop;
 select balance into cash from public.wallets where user_id=first_uid;
 select count(*) into count_before from public.casino_rounds where user_id=first_uid;
 foreach invalid in array array[null,'number:37','number:-1','number:00','number:3.5','invalid'] loop
  begin perform public.casino_start('roulette',1,invalid,gen_random_uuid());raise exception 'TEST: invalid API bet accepted';
  exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 end loop;
 if (select balance from public.wallets where user_id=first_uid)<>cash or (select count(*) from public.casino_rounds where user_id=first_uid)<>count_before then raise exception 'TEST: invalid bet charged';end if;
 begin perform public.casino_start('roulette',1.5,'green',gen_random_uuid());raise exception 'TEST: fractional stake accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 begin perform public.casino_start('roulette',1,'number:1',req);raise exception 'TEST: changed replay accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Request ID already used' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',second_uid::text,true);
 begin perform public.casino_start('roulette',1,choice,req);raise exception 'TEST: other member replay accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Request ID already used' then raise;end if;end;
 update public.profiles set frozen_until=clock_timestamp()+interval '1 hour' where id=second_uid;
 begin perform public.casino_start('roulette',1,'green',gen_random_uuid());raise exception 'TEST: frozen member played';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Account timed out%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',first_uid::text,true);
 r:=public.casino_start('roulette',17,'number:17',gen_random_uuid());
 if (r->>'max_payout')::numeric<>612 then raise exception 'TEST: larger roulette stake underfunded';end if;
 r:=public.casino_start('blackjack',20,null,gen_random_uuid());
 if (r->>'max_payout')::numeric<>50 then raise exception 'TEST: larger blackjack stake underfunded';end if;
 if r->>'status'='active' then perform public.casino_blackjack((r->>'id')::uuid,'stand',(r->>'version')::integer,gen_random_uuid());end if;
 update private.game_settings set casino_daily_limit=79 where id=1;
 begin perform public.casino_start('roulette',1,'green',gen_random_uuid());raise exception 'TEST: daily cap bypassed';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Daily games budget reached' then raise;end if;end;
 if (select sum(balance) from private.credit_accounts)<>initial_sum then raise exception 'TEST: credit supply changed';end if;
end $$;

set local role anon;
do $$begin
 begin perform public.casino_start('roulette',1,'green',gen_random_uuid());raise exception 'TEST: guest played';exception when insufficient_privilege then null;end;
end $$;
reset role;
set constraints all immediate;
select 'PASS: all 1554 bet/outcome combinations, validation, funded number and larger stakes, replay, ownership, daily limits, timeouts and credit conservation' as result;
rollback;
