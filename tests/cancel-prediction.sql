-- All fixtures, trades, loan draws and reset calls are rolled back. Never commit this file.
begin;
insert into private.invites values(encode(extensions.digest('cancel-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000a01','cancel_admin@members.multimarche.invalid','{"username":"cancel_admin","invite":"cancel-test-only"}'),
('00000000-0000-4000-8000-000000000a02','cancel_a@members.multimarche.invalid','{"username":"cancel_a","invite":"cancel-test-only"}'),
('00000000-0000-4000-8000-000000000a03','cancel_b@members.multimarche.invalid','{"username":"cancel_b","invite":"cancel-test-only"}'),
('00000000-0000-4000-8000-000000000a04','cancel_c@members.multimarche.invalid','{"username":"cancel_c","invite":"cancel-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000a01');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select set_config('test.amm',public.create_market_v7('Cancel AMM','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.2)::text,true);
select set_config('test.book',public.create_market_v7('Cancel book','Yes','No',now()+interval '1 day',2,false,'Count','clob',.5)::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.predict(current_setting('test.amm')::uuid,'yes',10,5,null,'GTC',null,0,gen_random_uuid());
do $$begin begin perform public.cancel_prediction(current_setting('test.amm')::uuid,true,100000,null,gen_random_uuid());raise exception 'TEST FAILED cancellation price guard';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if not exists(select 1 from public.positions where market_id=current_setting('test.amm')::uuid and shares>0) then raise exception 'Failed cancellation changed holding';end if;
end $$;
select set_config('test.cancel',gen_random_uuid()::text,true);
select public.cancel_prediction(current_setting('test.amm')::uuid,true,0,null,current_setting('test.cancel')::uuid);
select public.cancel_prediction(current_setting('test.amm')::uuid,true,0,null,current_setting('test.cancel')::uuid);
do $$begin
 if exists(select 1 from public.positions where market_id=current_setting('test.amm')::uuid and shares>0) or (select borrowed_balance from public.wallets)<>0 or abs((select balance from public.wallets)-1000)>.0000001 then raise exception 'Cancel did not flatten and repay exactly';end if;
end $$;
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,20,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,20,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.cancel_prediction(current_setting('test.book')::uuid,true,0,.5,gen_random_uuid());
do $$begin if (select reserved_shares from public.positions where market_id=current_setting('test.book')::uuid and side='yes')<>20 then raise exception 'Closing order must wait for real liquidity';end if;end $$;
reset role;
update public.profiles set frozen_until=now()+interval '1 hour' where id='00000000-0000-4000-8000-000000000a02';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.cancel_prediction(current_setting('test.book')::uuid,false,0,null,gen_random_uuid());
do $$begin if exists(select 1 from public.orders where market_id=current_setting('test.book')::uuid and status='open') then raise exception 'Timeout blocked pending cancellation';end if;
 begin perform public.cancel_prediction(current_setting('test.book')::uuid,true,0,.5,gen_random_uuid());raise exception 'TEST FAILED frozen close';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
reset role;
update public.profiles set frozen_until=null where id='00000000-0000-4000-8000-000000000a02';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.cancel_prediction(current_setting('test.book')::uuid,true,0,.5,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a04',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,20,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
do $$begin if exists(select 1 from public.positions where market_id=current_setting('test.book')::uuid and shares>0) then raise exception 'Matched closing order did not flatten';end if;end $$;
set local role anon;
do $$begin begin perform public.cancel_prediction(current_setting('test.book')::uuid,false,0,null,gen_random_uuid());raise exception 'TEST FAILED guest cancellation';exception when insufficient_privilege then null;end;end $$;
reset role;
set constraints all immediate;
do $$begin if (select sum(balance) from private.credit_accounts)<>(select total_supply from private.economy) then raise exception 'Supply mismatch';end if;end $$;
select 'PASS: guarded AMM cancellation, repayment, idempotency, real book liquidity, timeout/guest restrictions and conservation' result;
rollback;
