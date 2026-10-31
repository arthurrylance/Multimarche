-- All fixtures, trades, loan draws and reset calls are rolled back. Never commit this file.
begin;
insert into private.invites values(encode(extensions.digest('net-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000a01','net_admin@members.multimarche.invalid','{"username":"net_admin","invite":"net-test-only"}'),
('00000000-0000-4000-8000-000000000a02','net_a@members.multimarche.invalid','{"username":"net_a","invite":"net-test-only"}'),
('00000000-0000-4000-8000-000000000a03','net_b@members.multimarche.invalid','{"username":"net_b","invite":"net-test-only"}'),
('00000000-0000-4000-8000-000000000a04','net_c@members.multimarche.invalid','{"username":"net_c","invite":"net-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000a01');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select set_config('test.amm',public.create_market_v7('Low prior','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.1)::text,true);
select set_config('test.high',public.create_market_v7('High prior','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.9)::text,true);
select set_config('test.book',public.create_market_v7('Net book','Yes','No',now()+interval '1 day',2,false,'Count','clob',.3)::text,true);
do $$begin
 if (select probability from public.markets where id=current_setting('test.amm')::uuid)<>.1 then raise exception 'Low prior ignored';end if;
 begin perform public.create_market_v7('Invalid','Yes','No',now()+interval '1 hour',2,false,'Count','amm',0);raise exception 'TEST FAILED zero prior';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.trade(current_setting('test.amm')::uuid,'yes','buy',100,100,gen_random_uuid());
select public.trade(current_setting('test.amm')::uuid,'no','buy',40,100,gen_random_uuid());
do $$begin if (select shares from public.positions where market_id=current_setting('test.amm')::uuid and side='yes')<>60 or exists(select 1 from public.positions where market_id=current_setting('test.amm')::uuid and side='no' and shares>0) then raise exception 'AMM partial reversal failed';end if;end $$;
select public.trade(current_setting('test.amm')::uuid,'no','buy',80,100,gen_random_uuid());
do $$begin if (select shares from public.positions where market_id=current_setting('test.amm')::uuid and side='no')<>20 then raise exception 'AMM cross zero failed';end if;end $$;
select public.trade(current_setting('test.amm')::uuid,'yes','buy',20,100,gen_random_uuid());
-- AMM loan: one market, idempotency, protected collateral, normal settlement repayment.
select set_config('test.req',gen_random_uuid()::text,true);
select public.predict(current_setting('test.high')::uuid,'no',10,5,null,'GTC',null,0,current_setting('test.req')::uuid);
select public.predict(current_setting('test.high')::uuid,'no',10,5,null,'GTC',null,0,current_setting('test.req')::uuid);
do $$begin
 if (select count(*) from public.leverage_positions where status='active')<>1 or (select loan_collateral from public.wallets)<>40 then raise exception 'Loan not funded/idempotent';end if;
 begin perform public.predict(current_setting('test.amm')::uuid,'yes',10,10,null,'GTC',null,0,gen_random_uuid());raise exception 'TEST FAILED second loan';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
-- CLOB mint, reduce via direct transfer, cross zero, merge, reservation release.
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,10,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,10,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,20,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,15,'FOK',null,gen_random_uuid());
do $$begin
 if (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='yes')<>0 or (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='no')<>5 then raise exception 'CLOB crossing failed';end if;
end $$;
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,5,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,5,'GTC',null,gen_random_uuid());
-- A pending reduction reserves opposite shares, cancels safely, leaves only one direction.
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.1,12,'GTC',null,gen_random_uuid());
select public.cancel_my_orders(current_setting('test.book')::uuid);
do $$begin if exists(select 1 from public.positions where market_id=current_setting('test.book')::uuid and reserved_shares<>0) or (select reserved_balance from public.wallets)<>0 then raise exception 'Net cancellation leaked collateral';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.high')::uuid,'settle','{"outcome":"yes"}','Loan loss fixture');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
do $$begin if (select loan_collateral from public.wallets)<>0 or exists(select 1 from public.leverage_positions where status='active') then raise exception 'Loss did not repay loan';end if;end $$;
select public.predict(current_setting('test.amm')::uuid,'yes',10,10,null,'GTC',null,0,gen_random_uuid());
-- No authenticated helper access.
do $$begin begin perform private.settle_finished_loans(null,null);raise exception 'TEST FAILED helper exposed';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
set constraints all deferred;
do $$begin if (select sum(balance) from private.credit_accounts)<>(select total_supply from private.economy) then raise exception 'Supply changed';end if;end $$;
-- Shared emergency cooldown is exercised within the rollback transaction, never broadcast.
update public.emergency_signal set triggered_at=now()-interval '119 seconds' where id=1;
select set_config('test.version',(select version::text from public.emergency_signal where id=1),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.trigger_emergency();
do $$begin if (select version from public.emergency_signal where id=1)<>current_setting('test.version')::bigint then raise exception 'Emergency cooldown bypassed';end if;end $$;
-- Reset is tested only under rollback: permissions, explicit confirmation, repayment, balances, idempotency.
do $$begin begin perform public.admin_reset_economy('RESET ALL','Fixture reset',gen_random_uuid());raise exception 'TEST FAILED member reset';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select set_config('test.reset',gen_random_uuid()::text,true);
select public.admin_reset_economy('RESET ALL','Rollback fixture',current_setting('test.reset')::uuid);
select public.admin_reset_economy('RESET ALL','Rollback fixture',current_setting('test.reset')::uuid);
reset role;
do $$begin
 if exists(select 1 from public.wallets w join public.profiles p on p.id=w.user_id where w.balance<>case when p.active then 1000 else 0 end or w.loan_collateral<>0 or w.reserved_balance<>0) then raise exception 'Reset left wrong balances';end if;
 if exists(select 1 from public.markets where status<>'resolved' or not archived) or exists(select 1 from public.orders where status='open') or exists(select 1 from public.leverage_positions where status='active') then raise exception 'Reset left active exposure';end if;
 if (select total_supply::text from private.economy)<>current_setting('test.supply') then raise exception 'Reset changed supply';end if;
end $$;
set constraints all immediate;
rollback;
