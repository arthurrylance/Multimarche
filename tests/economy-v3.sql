-- AMM fixtures intentionally use private legacy creation helpers; public APIs now create order books.
begin;
insert into private.invites values(encode(extensions.digest('v3-test-only','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000201','v3_admin@members.multimarche.invalid','{"username":"v3_admin","invite":"v3-test-only"}'),
('00000000-0000-4000-8000-000000000202','v3_member@members.multimarche.invalid','{"username":"v3_member","invite":"v3-test-only"}'),
('00000000-0000-4000-8000-000000000203','v3_other@members.multimarche.invalid','{"username":"v3_other","invite":"v3-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000201');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000201',true);
select set_config('test.v3market',private.create_market_v3('X','Y','N',now()+interval '40 minutes',400,3)::text,true);
do $$declare mid uuid:=current_setting('test.v3market')::uuid;longid uuid;
begin
 longid:=private.create_market_v3(repeat('A',300),repeat('Y',4000),repeat('N',4000),now()+interval '40 minutes',400,2);
 if (select length(title) from public.markets where id=longid)<>300 then raise exception 'Title length restriction remains';end if;
 begin perform private.create_market_v3('Q','Y','N',now()+interval '1 hour',400,1);raise exception 'TEST FAILED one verifier accepted';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.trade(mid,'yes','buy',10,100,gen_random_uuid());
 perform public.resolve_market(mid,'yes','');
 if (select status from public.markets where id=mid)<>'proposed' then raise exception 'First vote did not pause';end if;
 perform public.admin_set_role('00000000-0000-4000-8000-000000000202',true);
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000202',true);
do $$begin
 if not public.is_admin() then raise exception 'Promotion failed';end if;
 perform public.resolve_market(current_setting('test.v3market')::uuid,'yes',repeat('E',3000));
 if (select status from public.markets where id=current_setting('test.v3market')::uuid)<>'proposed' then raise exception 'Settled before third confirmation';end if;
 perform public.withdraw_resolution(current_setting('test.v3market')::uuid);
 if (select status from public.markets where id=current_setting('test.v3market')::uuid)<>'proposed' then raise exception 'Withdrawal reopened despite remaining vote';end if;
 perform public.resolve_market(current_setting('test.v3market')::uuid,'yes','');
 insert into public.notification_reads(user_id,event_key) values('00000000-0000-4000-8000-000000000202','test-event');
 begin insert into public.notification_reads(user_id,event_key) values('00000000-0000-4000-8000-000000000201','forbidden');raise exception 'TEST FAILED cross-user notification write';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000203',true);
do $$declare mid uuid:=current_setting('test.v3market')::uuid;
begin
 if exists(select 1 from public.notification_reads) then raise exception 'Cross-user notification read';end if;
 begin perform public.admin_set_role('00000000-0000-4000-8000-000000000203',true);raise exception 'TEST FAILED self-promotion';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.resolve_market(mid,'yes','');
 if (select status from public.markets where id=mid)<>'resolved' then raise exception 'Third vote did not settle';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000201',true);
do $$declare mid uuid;
begin
 mid:=private.create_market_v3('Z','Y','N',now()+interval '1 hour',400,9);
 perform public.admin_market(mid,'settle','{"outcome":"no"}','');
 if not exists(select 1 from public.markets where id=mid and status='resolved' and admin_resolved) then raise exception 'Admin override failed';end if;
 perform public.admin_set_role('00000000-0000-4000-8000-000000000202',false);
 if not public.verify_audit() then raise exception 'Audit chain invalid';end if;
end $$;
reset role;
-- Isolate the last-admin guard inside this rollback-only transaction.
delete from private.admins where user_id<>'00000000-0000-4000-8000-000000000201';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000201',true);
do $$begin
 begin perform public.admin_set_role('00000000-0000-4000-8000-000000000201',false);raise exception 'TEST FAILED last admin removed';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
reset role;
set constraints all immediate;
select 'PASS: unrestricted event text, explicit Yes/No rules, minimum verifier count, three-member settlement, safe withdrawal, admin override, role promotion/revocation/last-admin guard, private notification read state, funded accounting' result;
rollback;
