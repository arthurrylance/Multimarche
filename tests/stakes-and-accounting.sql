-- Isolated rollback fixtures only. No global money reset or persistent configuration changes.
begin;
set local statement_timeout='10s';set local lock_timeout='2s';
insert into private.invites values(encode(extensions.digest('position-metrics-fixture','sha256'),'hex'),2,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000d01','position_metrics_fixture@members.multimarche.invalid','{"username":"position_metrics_fixture","invite":"position-metrics-fixture"}'),
('00000000-0000-4000-8000-000000000d02','position_other_fixture@members.multimarche.invalid','{"username":"position_other_fixture","invite":"position-metrics-fixture"}');
select set_config('test.supply',(select total_supply::text from private.economy where id=1),true);
update private.game_settings set casino_daily_limit=100 where id=1;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000d01',true);
select set_config('test.plinko',gen_random_uuid()::text,true);
select public.casino_plinko_batch(25,3,current_setting('test.plinko')::uuid);
do $$declare cash numeric;v numeric;begin
 select balance into cash from public.wallets where user_id=auth.uid();
 perform public.casino_plinko_batch(25,3,current_setting('test.plinko')::uuid);
 if (select balance from public.wallets where user_id=auth.uid())<>cash or (public.casino_state()->>'remaining')::numeric<>25 then raise exception 'Larger stake retry/budget failed';end if;
 begin perform public.casino_plinko_batch(20,2,gen_random_uuid());raise exception 'TEST: partial batch accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Daily games budget reached' then raise;end if;end;
 if (select balance from public.wallets where user_id=auth.uid())<>cash then raise exception 'Failed batch charged';end if;
 foreach v in array array['NaN'::numeric,'Infinity'::numeric,-1,0,1.5] loop begin perform public.casino_plinko_batch(v,1,gen_random_uuid());raise exception 'TEST: invalid stake accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Choose a whole-credit%' then raise;end if;end;end loop;
 begin perform public.casino_start('roulette',6,'red',gen_random_uuid());raise exception 'TEST: changed roulette cap';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Choose a stake%' then raise;end if;end;
 perform public.casino_plinko_batch(25,1,gen_random_uuid());
 if (public.casino_state()->>'remaining')::numeric<>0 then raise exception 'Daily cap not reached';end if;
end $$;
select set_config('test.market',public.create_market_v7('Position metrics fixture','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.5)::text,true);
select public.trade(current_setting('test.market')::uuid,'yes','buy',100,100,gen_random_uuid());
select set_config('test.paid',(public.position_accounting(current_setting('test.market')::uuid)->>'yes'),true);
select public.trade(current_setting('test.market')::uuid,'no','buy',40,100,gen_random_uuid());
do $$declare p jsonb;begin p:=public.position_accounting(current_setting('test.market')::uuid);if abs((p->>'yes')::numeric-current_setting('test.paid')::numeric*.6)>.000001 then raise exception 'Remaining weighted cost incorrect';end if;end $$;
select public.trade(current_setting('test.market')::uuid,'no','buy',80,100,gen_random_uuid());
do $$declare p jsonb;paid numeric;begin
 p:=public.position_accounting(current_setting('test.market')::uuid);select total into paid from public.trades where market_id=current_setting('test.market')::uuid and user_id=auth.uid() and side='no' and action='buy' order by sequence desc limit 1;
 if (p->>'yes')::numeric<>0 or (p->>'no')::numeric<>paid then raise exception 'Opposite position cost incorrect';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000d02',true);
do $$declare p jsonb;begin p:=public.position_accounting(current_setting('test.market')::uuid);if (p->>'yes')::numeric<>0 or (p->>'no')::numeric<>0 or (p->>'spent')::numeric<>0 then raise exception 'Another member accounting leaked';end if;end $$;
reset role;
do $$begin if has_function_privilege('anon','public.position_accounting(uuid)','execute') then raise exception 'Guest accounting exposed';end if;if (select sum(balance) from private.credit_accounts)<>current_setting('test.supply')::numeric then raise exception 'Issued supply changed';end if;end $$;
set constraints all immediate;
select 'PASS: larger Plinko stakes, atomic daily cap, retry safety, weighted position cost, own-account access and conserved credits' result;
rollback;
