-- All fixtures, trades, loan draws and reset calls are rolled back. Never commit this file.
begin;
insert into private.invites values(encode(extensions.digest('debt-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000a01','debt_admin@members.multimarche.invalid','{"username":"debt_admin","invite":"debt-test-only"}'),
('00000000-0000-4000-8000-000000000a02','debt_a@members.multimarche.invalid','{"username":"debt_a","invite":"debt-test-only"}'),
('00000000-0000-4000-8000-000000000a03','debt_b@members.multimarche.invalid','{"username":"debt_b","invite":"debt-test-only"}'),
('00000000-0000-4000-8000-000000000a04','debt_c@members.multimarche.invalid','{"username":"debt_c","invite":"debt-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000a01');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select set_config('test.amm',public.create_market_v7('Borrowed AMM','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select set_config('test.book',public.create_market_v7('Borrowed book','Yes','No',now()+interval '1 day',2,false,'Count','clob',.5)::text,true);
select set_config('test.empty',public.create_market_v7('Pending','Yes','No',now()+interval '1 day',2,false,'Count','clob',.5)::text,true);
reset role;
update public.wallets set balance=10 where user_id='00000000-0000-4000-8000-000000000a02';
insert into public.ledger(user_id,amount,reason) values('00000000-0000-4000-8000-000000000a02',-990,'Rollback fixture stake');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select set_config('test.req',gen_random_uuid()::text,true);
select public.predict(current_setting('test.amm')::uuid,'yes',10,10,null,'GTC',null,0,current_setting('test.req')::uuid);
select public.predict(current_setting('test.amm')::uuid,'yes',10,10,null,'GTC',null,0,current_setting('test.req')::uuid);
do $$begin
 if (select borrowed_balance from public.wallets)<>90 or (select balance from public.wallets)>0.0001 then raise exception 'Did not lend 90 against only 10 stake';end if;
 begin perform public.predict(current_setting('test.book')::uuid,'yes',1,5,.5,'GTC',null,0,gen_random_uuid());raise exception 'TEST FAILED second leveraged market';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.amm')::uuid,'settle','{"outcome":"no"}','Borrowed loss fixture');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
do $$begin
 if (select balance from public.wallets) not between -90 and -89.9999 or (select borrowed_balance from public.wallets)<>0 then raise exception 'Loss did not settle into negative balance';end if;
 begin perform public.predict(current_setting('test.book')::uuid,'yes',1,5,.5,'GTC',null,0,gen_random_uuid());raise exception 'TEST FAILED borrowed with negative stake';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,1,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED unfunded ordinary order';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
-- The same borrowing works for matched order books.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.5,100,'GTC',null,gen_random_uuid());
reset role;
update public.wallets set balance=10 where user_id='00000000-0000-4000-8000-000000000a04';
insert into public.ledger(user_id,amount,reason) values('00000000-0000-4000-8000-000000000a04',-990,'Rollback fixture stake');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
select public.predict(current_setting('test.book')::uuid,'yes',10,5,.5,'FOK',null,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.book')::uuid,'settle','{"outcome":"no"}','Borrowed book loss');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
do $$begin if (select balance from public.wallets)<>-40 then raise exception 'Book loss did not borrow stake only';end if;end $$;
-- Positive top-ups reduce a negative balance naturally.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_credit('00000000-0000-4000-8000-000000000a04',50,'Debt recovery fixture',gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
do $$begin if (select balance from public.wallets)<>10 then raise exception 'Credit did not repay negative balance';end if;end $$;
-- FOK failure and cancellation repay a loan without losing stake.
do $$begin begin perform public.predict(current_setting('test.empty')::uuid,'yes',10,10,.5,'FOK',null,0,gen_random_uuid());raise exception 'TEST FAILED empty leveraged FOK';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if exists(select 1 from public.leverage_positions where status='active') then raise exception 'FOK leaked debt';end if;
end $$;
select public.predict(current_setting('test.empty')::uuid,'yes',10,10,.5,'GTC',null,0,gen_random_uuid());
select public.cancel_my_orders(current_setting('test.empty')::uuid);
do $$begin if (select balance from public.wallets)<>10 or (select borrowed_balance from public.wallets)<>0 then raise exception 'Cancellation consumed stake';end if;end $$;
reset role;
set constraints all immediate;
set constraints all deferred;
do $$begin
 if (select sum(balance) from private.credit_accounts)<>(select total_supply from private.economy) then raise exception 'Supply changed';end if;
 begin perform private.transfer('user:00000000-0000-4000-8000-000000000a02','treasury',1,'Leverage repayment',null);raise exception 'TEST FAILED repayment without active loan';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
do $$begin if not public.verify_audit() then raise exception 'Audit hash chain failed';end if;end $$;
-- A winner repays principal and keeps the leveraged profit.
select set_config('test.win',public.create_market_v7('Loan win','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select set_config('test.reserve',public.create_market_v7('Loan reservation','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
select public.predict(current_setting('test.win')::uuid,'yes',10,5,null,'GTC',null,0,gen_random_uuid());
select set_config('test.payout',(select shares::text from public.positions where market_id=current_setting('test.win')::uuid and side='yes'),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.win')::uuid,'settle','{"outcome":"yes"}','Loan profit fixture');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
do $$begin if (select balance from public.wallets) not between current_setting('test.payout')::numeric-40 and current_setting('test.payout')::numeric-39.9999 then raise exception 'Win did not deduct principal';end if;end $$;
-- Unrelated pending buy orders are released if a repayment would make them unfunded.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.predict(current_setting('test.reserve')::uuid,'yes',100,5,null,'GTC',null,0,gen_random_uuid());
select public.place_order(current_setting('test.empty')::uuid,'yes','buy',.1,9000,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.reserve')::uuid,'settle','{"outcome":"no"}','Reservation cleanup fixture');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
do $$begin if (select reserved_balance from public.wallets)<>0 or exists(select 1 from public.orders where market_id=current_setting('test.empty')::uuid and status='open') then raise exception 'Repayment left unfunded pending orders';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
-- Reset still works with negative accounts, without issuing credits. Rolled back with all fixtures.
select public.admin_reset_economy('RESET ALL','Debt reset rollback only',gen_random_uuid());
reset role;
do $$begin if exists(select 1 from public.wallets w join public.profiles p on p.id=w.user_id where p.active and w.balance<>1000) then raise exception 'Reset mishandled negative accounts';end if;end $$;
set constraints all immediate;
select 'PASS: stake-only AMM/book borrowing, actual negative balances, replay protection, loan limit, failed FOK/cancellation, top-ups, ledger conservation and negative-account reset' result;
rollback;
