-- Entire scenario rolls back, including fixture users, fills, audit blocks and cash.
begin;
insert into private.invites values(encode(extensions.digest('book-test-only','sha256'),'hex'),5,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000801','book_admin@members.multimarche.invalid','{"username":"book_admin","invite":"book-test-only"}'),
('00000000-0000-4000-8000-000000000802','book_a@members.multimarche.invalid','{"username":"book_a","invite":"book-test-only"}'),
('00000000-0000-4000-8000-000000000803','book_b@members.multimarche.invalid','{"username":"book_b","invite":"book-test-only"}'),
('00000000-0000-4000-8000-000000000804','book_c@members.multimarche.invalid','{"username":"book_c","invite":"book-test-only"}'),
('00000000-0000-4000-8000-000000000805','book_d@members.multimarche.invalid','{"username":"book_d","invite":"book-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000801');
select set_config('test.treasury',(select balance::text from private.credit_accounts where id='treasury'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select set_config('test.book',public.create_market_v5('Book fixture','Yes','No',now()+interval '1 hour',2,true,'Count')::text,true);
select set_config('test.empty',public.create_market_v4('Compatibility fixture','Yes','No',now()+interval '1 hour',400,2,false,'Count')::text,true);
do $$begin
 if (select execution_model from public.markets where id=current_setting('test.empty')::uuid)<>'clob' then raise exception 'Old client created AMM';end if;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.12345,1,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED invalid price tick';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,'NaN'::numeric,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED NaN quantity';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,1,'GTD',now()-interval '1 minute',gen_random_uuid());raise exception 'TEST FAILED expired GTD';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if (select price_available from public.markets where id=current_setting('test.book')::uuid) then raise exception 'Invented an initial price';end if;
 begin perform public.trade(current_setting('test.book')::uuid,'yes','buy',1,100,gen_random_uuid());raise exception 'TEST FAILED AMM entry into CLOB';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
select set_config('test.buy_a',(public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,100,'GTC',null,'00000000-0000-4000-8000-000000000811')->>'id'),true);
do $$begin
 if (select reserved_balance from public.wallets)<>60 or (select balance from public.wallets)<>1000 then raise exception 'Unfilled reservation changed total money';end if;
 if exists(select 1 from public.positions where market_id=current_setting('test.book')::uuid) then raise exception 'Unfilled order created shares';end if;
 perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,100,'GTC',null,'00000000-0000-4000-8000-000000000811');
 if jsonb_array_length(public.get_my_orders(null))<>1 then raise exception 'Placement retry duplicated order';end if;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.61,100,'GTC',null,'00000000-0000-4000-8000-000000000811');raise exception 'TEST FAILED conflicting request';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','sell',.5,1,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED naked sell';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000803',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,60,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
do $$declare o public.orders;
begin
 select * into o from public.orders where id=current_setting('test.buy_a')::uuid;
 if o.filled<>60 or o.remaining<>40 or o.status<>'open' then raise exception 'Complementary partial fill failed';end if;
 if (select balance from public.wallets)<>964 or (select reserved_balance from public.wallets)<>24 then raise exception 'Partial buy accounting failed';end if;
 if (select shares from public.positions where market_id=o.market_id and side='yes')<>60 then raise exception 'Shares not created';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000804',true);
select set_config('test.buy_c',(public.place_order(current_setting('test.book')::uuid,'no','buy',.45,100,'GTC',null,gen_random_uuid())->>'id'),true);
do $$begin
 if (select balance from public.wallets)<>984 or (select reserved_balance from public.wallets)<>27 then raise exception 'Maker-price improvement failed';end if;
 begin perform public.cancel_order(current_setting('test.buy_a')::uuid);raise exception 'TEST FAILED cancelled other member order';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.cancel_order(current_setting('test.buy_c')::uuid);
 if (select reserved_balance from public.wallets)<>0 then raise exception 'Cancellation did not release cash';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
select set_config('test.ask_a',(public.place_order(current_setting('test.book')::uuid,'yes','sell',.65,20,'GTC',null,gen_random_uuid())->>'id'),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000805',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.7,10,'FOK',null,gen_random_uuid());
select set_config('test.ask_d',(public.place_order(current_setting('test.book')::uuid,'yes','sell',.65,5,'GTC',null,gen_random_uuid())->>'id'),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
do $$begin begin perform public.place_order(current_setting('test.book')::uuid,'yes','sell',.7,81,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED share double pledge';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000803',true);
select set_config('test.better',(public.place_order(current_setting('test.book')::uuid,'no','buy',.4,5,'GTC',null,gen_random_uuid())->>'id'),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.7,12,'FOK',null,gen_random_uuid());
do $$begin
 if (select coalesce(sum(quantity),0) from public.order_fills where maker_order_id=current_setting('test.better')::uuid)<>5 then raise exception 'Best effective price did not beat earlier worse price';end if;
 if (select coalesce(sum(quantity),0) from public.order_fills where maker_order_id=current_setting('test.ask_a')::uuid)<>17 or exists(select 1 from public.order_fills where maker_order_id=current_setting('test.ask_d')::uuid) then raise exception 'FIFO at equal price failed';end if;
end $$;
do $$declare fills_before integer;cash numeric;reserved numeric;orders_before integer;
begin
 if (select status from public.orders where id=current_setting('test.ask_a')::uuid) is not null then raise exception 'RLS exposed another user order';end if;
 select count(*) into fills_before from public.order_fills where market_id=current_setting('test.book')::uuid;
 select balance,reserved_balance into cash,reserved from public.wallets;
 select count(*) into orders_before from public.orders;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.7,100,'FOK',null,gen_random_uuid());raise exception 'TEST FAILED FOK partial commit';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if (select count(*) from public.order_fills where market_id=current_setting('test.book')::uuid)<>fills_before or (select balance from public.wallets)<>cash or (select reserved_balance from public.wallets)<>reserved or (select count(*) from public.orders)<>orders_before then raise exception 'Failed FOK left side effects';end if;
end $$;
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.7,10,'FAK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000803',true);
select public.place_order(current_setting('test.book')::uuid,'no','sell',.4,5,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
select public.place_order(current_setting('test.book')::uuid,'yes','sell',.6,5,'FOK',null,gen_random_uuid());
-- Same-owner complementary orders cancel the resting maker instead of self-trading.
select public.place_order(current_setting('test.empty')::uuid,'yes','buy',.6,10,'GTC',null,gen_random_uuid());
select public.place_order(current_setting('test.empty')::uuid,'no','buy',.5,10,'GTC',null,gen_random_uuid());
do $$begin if exists(select 1 from public.order_fills where market_id=current_setting('test.empty')::uuid) then raise exception 'Self trade executed';end if;if jsonb_array_length(public.orderbook(current_setting('test.empty')::uuid)->'orders')<>2 then raise exception 'Self trade history missing';end if;end $$;
-- Double-pledging funds is rejected across markets.
select public.cancel_my_orders(null);
select public.place_order(current_setting('test.empty')::uuid,'yes','buy',.5,1800,'GTC',null,gen_random_uuid());
do $$begin begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,1800,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED cash double pledge';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select public.admin_timeout('00000000-0000-4000-8000-000000000802',15);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
do $$begin if (select reserved_balance from public.wallets)<>0 then raise exception 'Timeout left funds reserved';end if;begin perform public.place_order(current_setting('test.empty')::uuid,'yes','buy',.5,1,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED frozen order';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select public.admin_timeout('00000000-0000-4000-8000-000000000802',0);
select set_config('test.expiring',(public.place_order(current_setting('test.empty')::uuid,'yes','buy',.3,5,'GTD',now()+interval '1 minute',gen_random_uuid())->>'id'),true);
reset role;
update public.orders set expires_at=now()-interval '1 second' where id=current_setting('test.expiring')::uuid;
do $$begin
 if (select filled from public.orders where id=current_setting('test.ask_a')::uuid)<>20 or (select filled from public.orders where id=current_setting('test.ask_d')::uuid)<>5 then raise exception 'Price-time FIFO failed';end if;
 if (select q_yes from public.markets where id=current_setting('test.book')::uuid)<>100 or (select q_no from public.markets where id=current_setting('test.book')::uuid)<>100 or (select balance from private.credit_accounts where id='market:'||current_setting('test.book'))<>100 then raise exception 'Pair merge collateral failed';end if;
 if exists(select 1 from public.wallets where reserved_balance<0 or reserved_balance>balance) then raise exception 'Invalid cash hold';end if;
 begin update public.order_fills set quantity=999 where market_id=current_setting('test.book')::uuid;raise exception 'TEST FAILED fill tampering';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select public.sync_orders();
do $$begin if (select status from public.orders where id=current_setting('test.expiring')::uuid)<>'expired' then raise exception 'Expiry not processed';end if;end $$;
select public.place_order(current_setting('test.empty')::uuid,'yes','buy',.2,5,'GTC',null,gen_random_uuid());
select public.admin_market(current_setting('test.empty')::uuid,'pause','{}','Book fixture');
do $$begin if (select reserved_balance from public.wallets)<>0 then raise exception 'Pause did not cancel pending orders';end if;end $$;
select public.admin_market(current_setting('test.book')::uuid,'settle','{"outcome":"yes"}','Book fixture settlement');
select public.admin_market(current_setting('test.empty')::uuid,'settle','{"outcome":"void"}','Empty fixture settlement');
-- Filled No and Void payouts use the ordinary two-member confirmation path.
select set_config('test.no',public.create_market_v5('No settlement fixture','Yes','No',now()+interval '1 hour',2,false,'Count')::text,true);
select set_config('test.void',public.create_market_v5('Void settlement fixture','Yes','No',now()+interval '1 hour',2,false,'Count')::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
select public.place_order(current_setting('test.no')::uuid,'yes','buy',.25,10,'GTC',null,gen_random_uuid());
select public.place_order(current_setting('test.void')::uuid,'yes','buy',.25,10,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000803',true);
select public.place_order(current_setting('test.no')::uuid,'no','buy',.75,10,'FOK',null,gen_random_uuid());
select public.place_order(current_setting('test.void')::uuid,'no','buy',.75,10,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
select public.place_order(current_setting('test.no')::uuid,'yes','buy',.1,5,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000802',true);
select public.resolve_market(current_setting('test.no')::uuid,'no','No occurred.');
select public.resolve_market(current_setting('test.void')::uuid,'void','Cannot determine.');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
do $$begin if (select reserved_balance from public.wallets)<>0 then raise exception 'Proposal did not cancel open orders';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000803',true);
select public.resolve_market(current_setting('test.no')::uuid,'no','Confirmed no.');
select public.resolve_market(current_setting('test.void')::uuid,'void','Confirmed void.');
do $$begin
 if (select amount from public.ledger where market_id=current_setting('test.no')::uuid and reason='Settlement: no')<>10 then raise exception 'No payout incorrect';end if;
 if (select amount from public.ledger where market_id=current_setting('test.void')::uuid and reason='Settlement: void')<>5 then raise exception 'Void payout incorrect';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000801',true);
do $$begin if not public.verify_audit() then raise exception 'Financial hash chain invalid';end if;begin insert into public.orders(request_id,user_id,market_id,side,action,price,quantity,tif,expires_at) values(gen_random_uuid(),auth.uid(),current_setting('test.book')::uuid,'yes','buy',.5,1,'GTC',now()+interval '1 hour');raise exception 'TEST FAILED direct order write';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if (select balance from private.credit_accounts where id='treasury')<>current_setting('test.treasury')::numeric then raise exception 'Treasury gained/lost money from player book';end if;
 if exists(select 1 from public.orders where market_id in(current_setting('test.book')::uuid,current_setting('test.empty')::uuid) and status='open') then raise exception 'Orders remained open after settlement';end if;
 if exists(select 1 from public.wallets where user_id::text like '00000000-0000-4000-8000-00000000080%' and reserved_balance<>0) then raise exception 'Reservation remained after settlement';end if;
end $$;
set local role anon;
do $$begin begin perform public.orderbook(current_setting('test.book')::uuid);raise exception 'TEST FAILED guest book';exception when insufficient_privilege then null;end;begin perform * from public.orders;raise exception 'TEST FAILED guest orders';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
select 'PASS: no treasury seed/profit, complementary mint and merge, direct trades, maker price improvement, price-time priority, partial fills, FOK rollback, FAK cancellation, idempotency, private orders, self-trade prevention, reservation limits, account timeout, expiry, pause, fully funded settlement and immutable audit' result;
rollback;
