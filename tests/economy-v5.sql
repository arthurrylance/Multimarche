-- AMM fixtures intentionally use private legacy creation helpers; public APIs now create order books.
-- Transactional fixtures only: no real accounts are removed and no credits persist.
begin;
insert into private.invites values(encode(extensions.digest('v5-test-only','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000501','v5_admin@members.multimarche.invalid','{"username":"v5_admin","invite":"v5-test-only"}'),
('00000000-0000-4000-8000-000000000502','v5_member@members.multimarche.invalid','{"username":"v5_member","invite":"v5-test-only"}'),
('00000000-0000-4000-8000-000000000503','v5_other@members.multimarche.invalid','{"username":"v5_other","invite":"v5-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000501');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000501',true);
select set_config('test.v5market',private.create_market_v4('Historical bet','It happened','It did not',now()+interval '40 minutes',400,2,false,'Count')::text,true);
select set_config('test.v5override',private.create_market_v4('Admin result','Yes','No',now()+interval '40 minutes',400,2,false,'Count')::text,true);
do $$begin
 begin perform public.market_history(current_setting('test.v5market')::uuid);raise exception 'TEST FAILED open market history';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.admin_delete_member(auth.uid());raise exception 'TEST FAILED self-deletion';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000502',true);
select public.trade(current_setting('test.v5market')::uuid,'yes','buy',10,100,gen_random_uuid());
select public.trade(current_setting('test.v5market')::uuid,'yes','sell',4,0,gen_random_uuid());
select public.acknowledge_notifications(array['v5:ended'],false);
select public.acknowledge_notifications(array['v5:ended'],true);
select public.acknowledge_notifications(array['v5:ended'],false);
do $$begin
 if not(select dismissed from public.notification_reads where event_key='v5:ended') then raise exception 'Read resurrected a cleared notification';end if;
 begin perform public.admin_delete_member('00000000-0000-4000-8000-000000000501');raise exception 'TEST FAILED member deleted admin';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000503',true);
do $$begin if exists(select 1 from public.notification_reads where event_key='v5:ended') then raise exception 'Another member read notification state';end if;end $$;
select public.trade(current_setting('test.v5market')::uuid,'no','buy',4,100,gen_random_uuid());
select public.resolve_market(current_setting('test.v5market')::uuid,'yes','Observed together');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000502',true);
select public.resolve_market(current_setting('test.v5market')::uuid,'yes','Second confirmation');
select set_config('test.member_cash',(select balance::text from public.wallets),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000501',true);
select public.admin_set_role('00000000-0000-4000-8000-000000000502',true);
select public.admin_market(current_setting('test.v5market')::uuid,'archive','{}','History fixture');
select public.admin_market(current_setting('test.v5override')::uuid,'settle','{"outcome":"void"}','Fixture admin override');
select public.admin_delete_member('00000000-0000-4000-8000-000000000502');
select public.admin_delete_member('00000000-0000-4000-8000-000000000502');
do $$declare h jsonb;t jsonb;
begin
 h:=public.market_history(current_setting('test.v5market')::uuid);
 if jsonb_array_length(h->'votes')<>2 or jsonb_array_length(h->'traders')<>2 then raise exception 'History lost confirmations/traders';end if;
 select value into t from jsonb_array_elements(h->'traders') where value->>'user_id'='00000000-0000-4000-8000-000000000502';
 if (t->>'yes_shares')::numeric<>6 or (t->>'payout')::numeric<>6 or (t->>'received')::numeric<=0 or (t->>'profit')::numeric<>(t->>'received')::numeric+6-(t->>'spent')::numeric then raise exception 'Historical payout or sale profit incorrect';end if;
 if exists(select 1 from public.leaderboard() where id='00000000-0000-4000-8000-000000000502') then raise exception 'Deleted member still ranked';end if;
 h:=public.market_history(current_setting('test.v5override')::uuid);
 if h->'admin_resolution'->>'user_id'<>auth.uid()::text or h->'admin_resolution'->>'reason'<>'Fixture admin override' then raise exception 'Missing admin resolution record';end if;
 if not public.verify_audit() then raise exception 'Audit invalid after deletion';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000502',true);
do $$begin
 if public.is_member() or public.is_admin() then raise exception 'Deleted account retains access';end if;
 if exists(select 1 from public.markets) or exists(select 1 from public.notification_reads) then raise exception 'Deleted account reads data with old JWT';end if;
 begin perform public.market_history(current_setting('test.v5market')::uuid);raise exception 'TEST FAILED removed history access';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.trigger_emergency();raise exception 'TEST FAILED removed emergency access';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.acknowledge_notifications(array['v5:new'],true);raise exception 'TEST FAILED removed notification write';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
reset role;
-- Simulate Auth identity clearing; profile sync must preserve historical names.
update auth.users set email='deleted-fixture@removed.invalid',raw_user_meta_data='{}' where id='00000000-0000-4000-8000-000000000502';
do $$begin
 if (select username from public.profiles where id='00000000-0000-4000-8000-000000000502')<>'v5_member' then raise exception 'Auth cleanup changed historical identity';end if;
 if (select balance from public.wallets where user_id='00000000-0000-4000-8000-000000000502')<>current_setting('test.member_cash')::numeric then raise exception 'Deletion changed funded balance';end if;
 if exists(select 1 from private.admins where user_id='00000000-0000-4000-8000-000000000502') then raise exception 'Deleted admin role retained';end if;
 if (select count(*) from public.admin_events where target_id='00000000-0000-4000-8000-000000000502' and action='member_deleted')<>1 then raise exception 'Deletion not idempotent';end if;
end $$;
set local role anon;
do $$begin begin perform public.market_history(current_setting('test.v5market')::uuid);raise exception 'TEST FAILED guest history access';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
select 'PASS: account removal, stale JWT denial, self/admin guards, immutable financial history, historical sales/payouts/confirmers, archived results, admin override attribution, notification ownership and persistent clearing' result;
rollback;
