-- AMM fixtures intentionally use private legacy creation helpers; public APIs now create order books.
begin;
insert into private.invites values(encode(extensions.digest('v7-test-only','sha256'),'hex'),2,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000701','v7_admin@members.multimarche.invalid','{"username":"v7_admin","invite":"v7-test-only"}'),
('00000000-0000-4000-8000-000000000702','v7_member@members.multimarche.invalid','{"username":"v7_member","invite":"v7-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000701');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000701',true);
select set_config('test.v7market',private.create_market_v4('Activity fixture','Yes','No',now()+interval '40 minutes',400,2,false,'Count')::text,true);
select public.presence_ping('00000000-0000-4000-8000-000000000711',true);
select public.presence_ping('00000000-0000-4000-8000-000000000712',true);
select public.trade(current_setting('test.v7market')::uuid,'yes','buy',10,100,gen_random_uuid());
reset role;
update public.trades set created_at=now()-interval '3 hours' where market_id=current_setting('test.v7market')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000701',true);
select public.trade(current_setting('test.v7market')::uuid,'yes','sell',1,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000702',true);
select public.presence_ping('00000000-0000-4000-8000-000000000713',true);
do $$declare result jsonb;entry jsonb;
begin
 result:=public.online_member_activity();
 select value into entry from jsonb_array_elements(result) where value->>'user_id'='00000000-0000-4000-8000-000000000701';
 if (entry->>'last_bet_at')::timestamptz<>now()-interval '3 hours' then raise exception 'Last buy lost or sell treated as a bet';end if;
 if (select count(*) from jsonb_array_elements(result) where value->>'user_id'='00000000-0000-4000-8000-000000000701')<>1 then raise exception 'Multiple tabs duplicated activity';end if;
 select value into entry from jsonb_array_elements(result) where value->>'user_id'=auth.uid()::text;
 if entry->>'last_bet_at' is not null then raise exception 'Invented a bet for a new user';end if;
 if not public.verify_audit() then raise exception 'Ledger affected';end if;
end $$;
reset role;
update public.member_presence set last_seen=now()-interval '2 minutes' where user_id='00000000-0000-4000-8000-000000000701';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000702',true);
do $$begin if exists(select 1 from jsonb_array_elements(public.online_member_activity()) where value->>'user_id'='00000000-0000-4000-8000-000000000701') then raise exception 'Stale member shown online';end if;end $$;
reset role;
update public.profiles set active=false where id='00000000-0000-4000-8000-000000000702';
set local role authenticated;
do $$begin begin perform public.online_member_activity();raise exception 'TEST FAILED removed member access';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
set local role anon;
do $$begin begin perform public.online_member_activity();raise exception 'TEST FAILED guest activity access';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
select 'PASS: authenticated online last-buy activity, duplicate-tab deduplication, no-bet state, sales excluded, stale presence expiry, guest/removed denial and unchanged ledger' result;
rollback;
