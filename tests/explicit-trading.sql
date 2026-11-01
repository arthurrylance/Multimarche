-- Isolated synthetic members only. Every fixture and transaction is rolled back.
begin;
set local statement_timeout='20s';set local lock_timeout='3s';
select set_config('test.supply',(select total_supply::text from private.economy where id=1),true);
insert into private.invites values(encode(extensions.digest('explicit-trading-fixture','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000e01','explicit_a@members.multimarche.invalid','{"username":"explicit_a","invite":"explicit-trading-fixture"}'),
('00000000-0000-4000-8000-000000000e02','explicit_b@members.multimarche.invalid','{"username":"explicit_b","invite":"explicit-trading-fixture"}'),
('00000000-0000-4000-8000-000000000e03','explicit_c@members.multimarche.invalid','{"username":"explicit_c","invite":"explicit-trading-fixture"}'),
('00000000-0000-4000-8000-000000000e04','explicit_d@members.multimarche.invalid','{"username":"explicit_d","invite":"explicit-trading-fixture"}');
insert into private.admins values('00000000-0000-4000-8000-000000000e01');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select set_config('test.amm',public.create_market_v7('Explicit AMM fixture','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.3)::text,true);
select set_config('test.book',public.create_market_v7('Explicit book fixture','Yes','No',now()+interval '1 hour',2,false,'Count','clob',.5)::text,true);
select set_config('test.loan',public.create_market_v7('Explicit loan fixture','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select set_config('test.loss',public.create_market_v7('Explicit loss fixture','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select public.execute_trade(current_setting('test.amm')::uuid,'yes','buy',25,1,null,'GTC',null,0,0,gen_random_uuid());
select set_config('test.yes',(select shares::text from public.positions where market_id=current_setting('test.amm')::uuid and side='yes'),true);
select set_config('test.req',gen_random_uuid()::text,true);
select public.execute_trade(current_setting('test.amm')::uuid,'no','buy',10,1,null,'GTC',null,0,0,current_setting('test.req')::uuid);
do $$declare cash numeric;begin
 select balance into cash from public.wallets;
 perform public.execute_trade(current_setting('test.amm')::uuid,'no','buy',10,1,null,'GTC',null,0,0,current_setting('test.req')::uuid);
 if (select balance from public.wallets)<>cash or (select shares from public.positions where market_id=current_setting('test.amm')::uuid and side='yes')<>current_setting('test.yes')::numeric then raise exception 'Buy netted opposite shares or replay duplicated';end if;
 begin perform public.execute_trade(current_setting('test.amm')::uuid,'no','sell',10,1,null,'GTC',null,0,0,current_setting('test.req')::uuid);raise exception 'TEST: conflicting nonce accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Request ID already used' then raise;end if;end;
end $$;
select set_config('test.no',(select shares::text from public.positions where market_id=current_setting('test.amm')::uuid and side='no'),true);
select set_config('test.basis',(public.position_accounting(current_setting('test.amm')::uuid)->>'yes'),true);
select public.execute_trade(current_setting('test.amm')::uuid,'yes','sell',10,1,null,'GTC',null,0,0,gen_random_uuid());
do $$begin
 if (select shares from public.positions where market_id=current_setting('test.amm')::uuid and side='no')<>current_setting('test.no')::numeric then raise exception 'Sale changed opposite holdings';end if;
 if abs((public.position_accounting(current_setting('test.amm')::uuid)->>'yes')::numeric-current_setting('test.basis')::numeric*(1-10/current_setting('test.yes')::numeric))>.000001 then raise exception 'Sale basis wrong';end if;
 begin perform public.execute_trade(current_setting('test.amm')::uuid,'no','sell',10000,1,null,'GTC',null,0,0,gen_random_uuid());raise exception 'TEST: naked sale';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 begin perform public.execute_trade(current_setting('test.amm')::uuid,'no','sell',1,5,null,'GTC',null,0,0,gen_random_uuid());raise exception 'TEST: leveraged sale';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 begin perform public.predict(current_setting('test.amm')::uuid,'no',1,1,null,'GTC',null,0,gen_random_uuid());raise exception 'TEST: stale netting client accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Trading controls changed%' then raise;end if;end;
end $$;
-- Complementary buy mint, direct transfer, complementary sell merge.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e02',true);
select public.execute_trade(current_setting('test.book')::uuid,'yes','buy',60,1,.6,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e03',true);
select public.execute_trade(current_setting('test.book')::uuid,'no','buy',40,1,.4,'FOK',null,0,0,gen_random_uuid());
select public.execute_trade(current_setting('test.book')::uuid,'no','sell',10,1,.5,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select public.execute_trade(current_setting('test.book')::uuid,'no','buy',5,1,.5,'FOK',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e03',true);
select public.execute_trade(current_setting('test.book')::uuid,'no','sell',10,1,.5,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e02',true);
select public.execute_trade(current_setting('test.book')::uuid,'yes','sell',10,1,.5,'FOK',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e03',true);
select public.execute_trade(current_setting('test.book')::uuid,'no','buy',4,1,.4,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select public.execute_trade(current_setting('test.book')::uuid,'yes','buy',6,1,.6,'FOK',null,0,0,gen_random_uuid());
do $$begin if (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='yes')<>10 or (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='no')<>10 then raise exception 'Book cannot hold both';end if;end $$;
select public.execute_trade(current_setting('test.book')::uuid,'yes','sell',3,1,.9,'GTC',null,0,0,gen_random_uuid());
select public.execute_trade(current_setting('test.book')::uuid,'no','buy',1,1,.1,'GTC',null,0,0,gen_random_uuid());
do $$declare cash numeric;cnt integer;begin
 if (select count(*) from public.orders where market_id=current_setting('test.book')::uuid and status='open')<>2 or (select reserved_shares from public.positions where market_id=current_setting('test.book')::uuid and side='yes')<>3 or (select reserved_balance from public.wallets)<>1 then raise exception 'Independent pending orders not preserved';end if;
 begin perform public.execute_trade(current_setting('test.book')::uuid,'yes','sell',8,1,.9,'GTC',null,0,0,gen_random_uuid());raise exception 'TEST: double pledged shares';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 select balance into cash from public.wallets;select count(*) into cnt from public.orders;
 begin perform public.execute_trade(current_setting('test.book')::uuid,'yes','buy',6,1,.6,'FOK',null,0,0,gen_random_uuid());raise exception 'TEST: FOK partial commit';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Not enough matching orders%' then raise;end if;end;
 if (select balance from public.wallets)<>cash or (select count(*) from public.orders)<>cnt then raise exception 'FOK leaked writes';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e02',true);
select public.execute_trade(current_setting('test.book')::uuid,'yes','buy',1,1,.5,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select public.execute_trade(current_setting('test.book')::uuid,'yes','sell',5,1,.5,'FAK',null,0,0,gen_random_uuid());
do $$begin if (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='yes')<>8 or (select shares from public.positions where market_id=current_setting('test.book')::uuid and side='no')<>10 then raise exception 'FAK or independent sale failed';end if;end $$;
select public.cancel_my_orders(current_setting('test.book')::uuid);
do $$begin if (select reserved_balance from public.wallets)<>0 or exists(select 1 from public.positions where market_id=current_setting('test.book')::uuid and reserved_shares<>0) then raise exception 'Cancel did not release';end if;end $$;
-- One loan, both holdings, debt stays until both sides close.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e04',true);
select public.execute_trade(current_setting('test.loan')::uuid,'yes','buy',10,5,null,'GTC',null,0,0,gen_random_uuid());
select public.execute_trade(current_setting('test.loan')::uuid,'no','buy',1,1,null,'GTC',null,0,0,gen_random_uuid());
do $$begin
 begin perform public.execute_trade(current_setting('test.loss')::uuid,'yes','buy',1,5,null,'GTC',null,0,0,gen_random_uuid());raise exception 'TEST: two loans allowed';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;
 perform public.execute_trade(current_setting('test.loan')::uuid,'yes','sell',(select shares from public.positions where market_id=current_setting('test.loan')::uuid and side='yes'),1,null,'GTC',null,0,0,gen_random_uuid());
 if not exists(select 1 from public.leverage_positions where market_id=current_setting('test.loan')::uuid and status='active' and remaining=40) then raise exception 'Debt settled before opposite holdings closed';end if;
 perform public.execute_trade(current_setting('test.loan')::uuid,'no','sell',(select shares from public.positions where market_id=current_setting('test.loan')::uuid and side='no'),1,null,'GTC',null,0,0,gen_random_uuid());
 if exists(select 1 from public.leverage_positions where market_id=current_setting('test.loan')::uuid and status='active') then raise exception 'Flat debt not repaid';end if;
end $$;
-- Preserve unsecured borrowing and negative balances after a loss.
reset role;
insert into public.ledger(user_id,amount,reason) select user_id,10-balance,'Rollback fixture stake' from public.wallets where user_id='00000000-0000-4000-8000-000000000e04';
update public.wallets set balance=10 where user_id='00000000-0000-4000-8000-000000000e04';
set local role authenticated;
select public.execute_trade(current_setting('test.loss')::uuid,'yes','buy',10,10,null,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select public.admin_market(current_setting('test.loss')::uuid,'settle','{"outcome":"no"}','Rollback loss test');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e04',true);
do $$begin if (select balance from public.wallets) not between -90 and -89.999 then raise exception 'Unsecured loss did not go negative';end if;end $$;
-- Independent settlement only pays the winning holding.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e01',true);
select set_config('test.cash',(select balance::text from public.wallets),true);
select public.admin_market(current_setting('test.amm')::uuid,'settle','{"outcome":"yes"}','Rollback dual holding settlement');
do $$begin if abs((select balance from public.wallets)-current_setting('test.cash')::numeric-(current_setting('test.yes')::numeric-10))>.000001 then raise exception 'Dual holding settlement incorrect';end if;end $$;
select public.admin_timeout('00000000-0000-4000-8000-000000000e02',15);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000e02',true);
do $$begin begin perform public.execute_trade(current_setting('test.book')::uuid,'yes','sell',1,1,.5,'GTC',null,0,0,gen_random_uuid());raise exception 'TEST: timeout ignored';exception when others then if sqlerrm like 'TEST:%' then raise;end if;end;end $$;
reset role;
set constraints all immediate;
do $$begin
 if has_function_privilege('anon','public.execute_trade(uuid,text,text,numeric,integer,numeric,text,timestamptz,numeric,numeric,uuid)','execute') then raise exception 'Guest trading exposed';end if;
 if (select sum(balance) from private.credit_accounts)<>current_setting('test.supply')::numeric then raise exception 'Credits not conserved';end if;
end $$;
select 'PASS: independent AMM/book buy/sell, dual holdings and settlement, reservations, direct/mint/merge, FOK/FAK, replay, stale-client guard, timeout, loan lifecycle and negative losses, conserved supply' result;
rollback;
