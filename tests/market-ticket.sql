-- Synthetic market-ticket execution check. No persistent data or wallet changes.
begin;
set local statement_timeout='20s';
set local lock_timeout='3s';
select set_config('test.ticket_supply',(select total_supply::text from private.economy where id=1),true);
insert into private.invites values(encode(extensions.digest('market-ticket-fixture','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000f01','ticket_a@members.multimarche.invalid','{"username":"ticket_a","invite":"market-ticket-fixture"}'),
('00000000-0000-4000-8000-000000000f02','ticket_b@members.multimarche.invalid','{"username":"ticket_b","invite":"market-ticket-fixture"}'),
('00000000-0000-4000-8000-000000000f03','ticket_c@members.multimarche.invalid','{"username":"ticket_c","invite":"market-ticket-fixture"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f01',true);
select set_config('test.ticket_market',public.create_market_v7('Market ticket fixture','Yes','No',now()+interval '1 hour',2,false,'Count','clob',.5)::text,true);
-- Complementary No bids offer 10 Yes shares at .4 and 5 at .6.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f02',true);
select public.execute_trade(current_setting('test.ticket_market')::uuid,'no','buy',6,1,.6,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f03',true);
select public.execute_trade(current_setting('test.ticket_market')::uuid,'no','buy',2,1,.4,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f01',true);
select set_config('test.ticket_before',(select balance::text from public.wallets),true);
select set_config('test.ticket_request',gen_random_uuid()::text,true);
-- Same payload as a 25-credit market buy from the new ticket: protected price,
-- FAK execution, independent shares, unfilled cash automatically released.
select public.execute_trade(current_setting('test.ticket_market')::uuid,'yes','buy',25,1,.603,'FAK',null,0,0,current_setting('test.ticket_request')::uuid);
do $$begin
 if (select shares from public.positions where market_id=current_setting('test.ticket_market')::uuid and side='yes')<>15 then raise exception 'Market buy did not walk both price levels';end if;
 if (select balance from public.wallets)<>current_setting('test.ticket_before')::numeric-7 then raise exception 'Market buy charged more than matched cost';end if;
 if (select reserved_balance from public.wallets)<>0 or exists(select 1 from public.orders where market_id=current_setting('test.ticket_market')::uuid and status='open') then raise exception 'Market remainder was left reserved or resting';end if;
 perform public.execute_trade(current_setting('test.ticket_market')::uuid,'yes','buy',25,1,.603,'FAK',null,0,0,current_setting('test.ticket_request')::uuid);
 if (select balance from public.wallets)<>current_setting('test.ticket_before')::numeric-7 then raise exception 'Market retry charged twice';end if;
end $$;
-- A 50% sale uses only the 10 shares not reserved by an existing limit sell.
select public.execute_trade(current_setting('test.ticket_market')::uuid,'yes','sell',5,1,.9,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f02',true);
select public.execute_trade(current_setting('test.ticket_market')::uuid,'yes','buy',2.5,1,.5,'GTC',null,0,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000f01',true);
select public.execute_trade(current_setting('test.ticket_market')::uuid,'yes','sell',5,1,.4975,'FAK',null,0,0,gen_random_uuid());
do $$begin
 if (select shares from public.positions where market_id=current_setting('test.ticket_market')::uuid and side='yes')<>10 or (select reserved_shares from public.positions where market_id=current_setting('test.ticket_market')::uuid and side='yes')<>5 then raise exception 'Market sale consumed reserved shares';end if;
end $$;
select public.cancel_my_orders(current_setting('test.ticket_market')::uuid);
reset role;
set constraints all immediate;
do $$begin
 if (select sum(balance) from private.credit_accounts)<>current_setting('test.ticket_supply')::numeric then raise exception 'Ticket trades changed credit supply';end if;
end $$;
select 'PASS: protected market buy walks depth, partial fill charges only matches, unused cash released, retry idempotency, available-share sale, preserved resting reservation, credit conservation' result;
rollback;
