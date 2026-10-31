-- AMM fixtures intentionally use private legacy creation helpers; public APIs now create order books.
-- Run as project owner. All fixture accounts and trades roll back.
begin;
insert into private.invites(code_hash,remaining,expires_at)
values(encode(extensions.digest('integration-test-only','sha256'),'hex'),5,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000001','test_one@members.multimarche.invalid','{"username":"integration_test_one","invite":"integration-test-only"}'),
('00000000-0000-4000-8000-000000000002','test_two@members.multimarche.invalid','{"username":"integration_test_two","invite":"integration-test-only"}');
do $$ begin
 if exists(select 1 from auth.users where id in ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002') and raw_user_meta_data ? 'invite') then raise exception 'Invite leaked into user metadata'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('test.market', private.create_market('Will this integration test pass?', 'Yes if all assertions pass. No otherwise.','Other','🧪',now()+interval '1 hour')::text,true);
do $$ declare mid uuid := current_setting('test.market')::uuid; t jsonb; initial numeric; begin
 select balance into initial from public.wallets;
 if initial<>1000 then raise exception 'Wrong starting balance'; end if;
 t:=public.trade(mid,'yes','buy',100,100,'00000000-0000-4000-8000-000000000010');
 if (select probability from public.markets where id=mid)<=0.5 then raise exception 'Odds did not move'; end if;
 perform public.trade(mid,'yes','buy',100,100,'00000000-0000-4000-8000-000000000010');
 if (select shares from public.positions where market_id=mid and side='yes')<>100 then raise exception 'Duplicate trade executed'; end if;
 perform public.trade(mid,'yes','sell',25,0,'00000000-0000-4000-8000-000000000011');
 if (select shares from public.positions where market_id=mid and side='yes')<>75 then raise exception 'Sell failed'; end if;
 begin perform public.trade(mid,'yes','sell',1000,0,gen_random_uuid()); raise exception 'TEST FAILED oversell accepted'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
 begin perform public.trade(mid,'no','buy',10000,10000,gen_random_uuid()); raise exception 'TEST FAILED overspend accepted'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
 begin perform public.trade(mid,'yes','buy','NaN',100,gen_random_uuid()); raise exception 'TEST FAILED NaN accepted'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
 begin update public.wallets set balance=999999; raise exception 'TEST FAILED wallet mutation accepted'; exception when insufficient_privilege then null; end;
 if (select count(*) from public.wallets)<>1 then raise exception 'Can read another wallet'; end if;
 perform public.resolve_market(mid,'yes','I independently observed the integration test pass.');
 if (select status from public.markets where id=mid)<>'proposed' then raise exception 'Must pause on proposal'; end if;
 begin perform public.trade(mid,'no','buy',1,100,gen_random_uuid()); raise exception 'TEST FAILED trading while paused'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
 begin perform public.resolve_market(mid,'yes','I am trying to confirm twice.'); raise exception 'TEST FAILED same person confirmed'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ declare mid uuid := current_setting('test.market')::uuid; begin
 if exists(select 1 from public.positions) then raise exception 'Can read another position'; end if;
 begin perform public.resolve_market(mid,'no','This conflicts with the proposed result.'); raise exception 'TEST FAILED conflicting confirmation'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
 perform public.resolve_market(mid,'yes','A second observer confirms the test passed.');
 if (select status from public.markets where id=mid)<>'resolved' then raise exception 'Not settled'; end if;
 begin perform public.resolve_market(mid,'yes','Trying to settle again.'); raise exception 'TEST FAILED double payout'; exception when others then if sqlerrm like 'TEST FAILED%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ declare mid uuid := current_setting('test.market')::uuid; begin
 if (select count(*) from public.ledger where market_id=mid and reason='Settlement: yes')<>1 then raise exception 'Wrong number of payouts'; end if;
 if (select amount from public.ledger where market_id=mid and reason='Settlement: yes')<>75 then raise exception 'Wrong payout'; end if;
 if abs((select balance from public.wallets)-(select sum(amount) from public.ledger))>0.00000001 then raise exception 'Ledger does not reconcile'; end if;
end $$;
set local role anon;
do $$ begin
 begin perform * from public.markets; raise exception 'TEST FAILED anonymous data access'; exception when insufficient_privilege then null; end;
 begin perform public.leaderboard(); raise exception 'TEST FAILED anonymous RPC'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: trading, selling, idempotency, odds, overspend/oversell, NaN, RLS, two-member resolution, single payout, ledger reconciliation, anonymous denial' as result;
rollback;
