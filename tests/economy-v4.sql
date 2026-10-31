-- AMM fixtures intentionally use private legacy creation helpers; public APIs now create order books.
-- All fixtures and the shared redirect signal are rolled back: no live broadcast.
begin;
insert into private.invites values(encode(extensions.digest('v4-test-only','sha256'),'hex'),2,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000301','v4_owner@members.multimarche.invalid','{"username":"v4_owner","invite":"v4-test-only"}'),
('00000000-0000-4000-8000-000000000302','v4_member@members.multimarche.invalid','{"username":"v4_member","invite":"v4-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000301');
update public.emergency_signal set triggered_at=now()-interval '1 hour' where id=1;
select set_config('test.signal_version',(select version::text from public.emergency_signal),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000301',true);
select set_config('test.v4market',private.create_market_v4('Count?','More than three','Three or fewer',now()+interval '40 minutes',400,2,true,'Etcetera count')::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000302',true);
do $$declare mid uuid:=current_setting('test.v4market')::uuid;cash numeric;version bigint;
begin
 select balance into cash from public.wallets;
 perform public.change_counter(mid,1,'00000000-0000-4000-8000-000000000311');
 perform public.change_counter(mid,1,'00000000-0000-4000-8000-000000000311');
 if (select counter_value from public.markets where id=mid)<>1 then raise exception 'Counter update not idempotent';end if;
 if (select probability from public.markets where id=mid)<>.5 then raise exception 'Counter changed odds';end if;
 if (select balance from public.wallets)<>cash then raise exception 'Counter changed credits';end if;
 begin perform public.change_counter(mid,-1,gen_random_uuid());raise exception 'TEST FAILED member decremented';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.set_counter_enabled(mid,false,'Hidden');raise exception 'TEST FAILED another member changed counter settings';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin update public.markets set counter_value=9999 where id=mid;raise exception 'TEST FAILED direct counter write';exception when insufficient_privilege then null;end;
 version:=public.trigger_emergency();
 if version<>current_setting('test.signal_version')::bigint+1 then raise exception 'Emergency signal not persisted';end if;
 if public.trigger_emergency()<>version then raise exception 'Emergency cooldown failed';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000301',true);
do $$declare mid uuid:=current_setting('test.v4market')::uuid;
begin
 perform public.change_counter(mid,-1,gen_random_uuid());
 begin perform public.change_counter(mid,-1,gen_random_uuid());raise exception 'TEST FAILED negative count';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.admin_market(mid,'settle','{"outcome":"void"}','Counter fixture complete');
 begin perform public.change_counter(mid,1,gen_random_uuid());raise exception 'TEST FAILED settled market updated';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if not public.verify_audit() then raise exception 'Accounting audit failed';end if;
end $$;
set local role anon;
do $$begin
 if (select count(*) from public.emergency_signal)<>1 then raise exception 'Visitors cannot receive emergency';end if;
 begin perform public.trigger_emergency();raise exception 'TEST FAILED guest triggered global redirect';exception when insufficient_privilege then null;end;
 begin update public.emergency_signal set version=999;raise exception 'TEST FAILED direct signal write';exception when insufficient_privilege then null;end;
 begin perform * from public.counter_events;raise exception 'TEST FAILED guest read counter history';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if to_regprocedure('public.set_chain(text,text)') is not null then raise exception 'Wallet setup API remains';end if;
 begin update public.counter_events set delta=100 where market_id=current_setting('test.v4market')::uuid;raise exception 'TEST FAILED edited counter history';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set constraints all immediate;
select 'PASS: persistent emergency signal, member-only broadcast, guest receive-only access, cooldown, live counter idempotency, ownership/admin checks, nonnegative counts, immutable history, no price/balance changes, settlement lock and funded ledger' result;
rollback;
