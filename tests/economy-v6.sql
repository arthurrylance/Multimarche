begin;
insert into private.invites values(encode(extensions.digest('v6-test-only','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000601','v6_admin@members.multimarche.invalid','{"username":"v6_admin","invite":"v6-test-only"}'),
('00000000-0000-4000-8000-000000000602','v6_member@members.multimarche.invalid','{"username":"v6_member","invite":"v6-test-only"}'),
('00000000-0000-4000-8000-000000000603','v6_other@members.multimarche.invalid','{"username":"v6_other","invite":"v6-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000601');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000601',true);
select set_config('test.v6market',public.create_market_v4('Loss check','Yes','No',now()+interval '40 minutes',400,2,false,'Count')::text,true);
select set_config('test.v6open',public.create_market_v4('Frozen check','Yes','No',now()+interval '40 minutes',400,2,true,'Count')::text,true);
select public.admin_nickname('00000000-0000-4000-8000-000000000602','New Nickname');
do $$begin
 if (select nickname from public.profiles where username='v6_member')<>'New Nickname' then raise exception 'Nickname not updated';end if;
 begin perform public.admin_nickname('00000000-0000-4000-8000-000000000602',repeat('x',41));raise exception 'TEST FAILED long nickname';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.admin_timeout(auth.uid(),15);raise exception 'TEST FAILED self timeout';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
select public.trade(current_setting('test.v6market')::uuid,'yes','buy',1000,1000,gen_random_uuid());
do $$declare report jsonb;
begin
 report:=public.loss_summary();if (report->>'triggered')::boolean or (report->>'loss')::numeric<>0 or (report->>'baseline')::numeric<>1000 then raise exception 'Open investment counted as a loss';end if;
 perform public.presence_ping('00000000-0000-4000-8000-000000000611',true);
 perform public.presence_ping('00000000-0000-4000-8000-000000000612',true);
 if jsonb_array_length(public.online_members())<>1 then raise exception 'Multiple tabs duplicated presence';end if;
 perform public.presence_ping('00000000-0000-4000-8000-000000000611',false);
 if jsonb_array_length(public.online_members())<>1 then raise exception 'Closing one tab removed the other';end if;
 begin insert into public.member_presence values(auth.uid(),gen_random_uuid(),now());raise exception 'TEST FAILED direct presence write';exception when insufficient_privilege then null;end;
 begin perform public.admin_nickname('00000000-0000-4000-8000-000000000601','Spoof');raise exception 'TEST FAILED nonadmin nickname';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.admin_timeout('00000000-0000-4000-8000-000000000601',15);raise exception 'TEST FAILED nonadmin timeout';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000601',true);
select public.admin_timeout('00000000-0000-4000-8000-000000000602',15);
do $$begin
 begin perform public.admin_set_role('00000000-0000-4000-8000-000000000602',true);raise exception 'TEST FAILED promoted frozen member';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
do $$declare mid uuid:=current_setting('test.v6open')::uuid;
begin
 if not public.is_member() or not exists(select 1 from public.markets where id=mid) then raise exception 'Frozen member cannot browse';end if;
 begin perform public.trade(mid,'yes','buy',1,100,gen_random_uuid());raise exception 'TEST FAILED frozen trade';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.create_market_v4('Bad','Yes','No',now()+interval '1 hour',400,2,false,'Count');raise exception 'TEST FAILED frozen create';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.create_market_v2('Bad','Rule','Other',now()+interval '1 hour',400);raise exception 'TEST FAILED frozen legacy create';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.resolve_market(mid,'yes','');raise exception 'TEST FAILED frozen result';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.withdraw_resolution(mid);raise exception 'TEST FAILED frozen withdraw';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.change_counter(mid,1,gen_random_uuid());raise exception 'TEST FAILED frozen count';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin insert into public.comments(user_id,market_id,body) values(auth.uid(),mid,'Forbidden while timed out');raise exception 'TEST FAILED frozen comment';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000601',true);
select public.admin_market(current_setting('test.v6market')::uuid,'settle','{"outcome":"no"}','Loss fixture');
select public.admin_history(current_setting('test.v6market')::uuid,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
do $$declare report jsonb;mid uuid:=current_setting('test.v6market')::uuid;
begin
 report:=public.loss_summary();if not (report->>'triggered')::boolean or (report->>'loss')::numeric<500 or (report->>'baseline')::numeric<>1000 then raise exception 'Realised loss threshold incorrect: %',report;end if;
 if exists(select 1 from public.markets where id=mid) or exists(select 1 from public.trades where market_id=mid) then raise exception 'Deleted history still visible';end if;
 begin perform public.market_history(mid);raise exception 'TEST FAILED hidden history RPC';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000601',true);
select public.admin_history(current_setting('test.v6market')::uuid,false);
select public.admin_timeout('00000000-0000-4000-8000-000000000602',0);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
select public.trade(current_setting('test.v6open')::uuid,'yes','buy',1,100,gen_random_uuid());
do $$begin if not exists(select 1 from public.markets where id=current_setting('test.v6market')::uuid) then raise exception 'Restore failed';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000603',true);
select public.presence_ping('00000000-0000-4000-8000-000000000611',true);
select public.trade(current_setting('test.v6open')::uuid,'no','buy',10,100,gen_random_uuid());
select public.trade(current_setting('test.v6open')::uuid,'no','sell',5,0,gen_random_uuid());
do $$declare report jsonb;
begin report:=public.loss_summary();if (report->>'loss')::numeric<0 or (report->>'baseline')::numeric<990 or (report->>'triggered')::boolean then raise exception 'Partial sales cost-basis accounting incorrect';end if;end $$;
reset role;
update public.member_presence set last_seen=now()-interval '2 minutes' where user_id='00000000-0000-4000-8000-000000000602';
update public.profiles set frozen_until=now()-interval '1 second' where id='00000000-0000-4000-8000-000000000602';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
select public.trade(current_setting('test.v6open')::uuid,'yes','buy',1,100,gen_random_uuid());
do $$begin if jsonb_array_length(public.online_members())<>1 then raise exception 'Stale presence did not expire';end if;if not public.verify_audit() then raise exception 'Ledger changed incorrectly';end if;end $$;
set local role anon;
do $$begin
 begin perform * from public.markets;raise exception 'TEST FAILED guest markets';exception when insufficient_privilege then null;end;
 begin perform public.online_members();raise exception 'TEST FAILED guest presence';exception when insufficient_privilege then null;end;
 begin perform public.loss_summary();raise exception 'TEST FAILED guest losses';exception when insufficient_privilege then null;end;
end $$;
reset role;
set constraints all immediate;
select 'PASS: nicknames, server timeouts and expiry, frozen read-only access, old API denial, role guards, hidden/restored history, preserved settlement/ledger, realised loss accounting, open-bet exclusion, multi-tab presence ownership/expiry, guest data denial' result;
rollback;
