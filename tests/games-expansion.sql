-- Rollback-only fixtures. No real members, money reset, or persistent setting changes.
begin;
set local statement_timeout='10s';set local lock_timeout='2s';
insert into private.invites values(encode(extensions.digest('games-expansion-fixture','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000c01','games_limits_fixture@members.multimarche.invalid','{"username":"games_limits_fixture","invite":"games-expansion-fixture"}'),
('00000000-0000-4000-8000-000000000c02','snake_a_fixture@members.multimarche.invalid','{"username":"snake_a_fixture","invite":"games-expansion-fixture"}'),
('00000000-0000-4000-8000-000000000c03','snake_b_fixture@members.multimarche.invalid','{"username":"snake_b_fixture","invite":"games-expansion-fixture"}');
insert into private.admins values('00000000-0000-4000-8000-000000000c01');
select set_config('test.supply',(select total_supply::text from private.economy where id=1),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000c02',true);
do $$begin
 begin perform public.admin_game_settings(10,gen_random_uuid());raise exception 'TEST: member changed casino limit';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Admin access required' then raise;end if;end;
 begin perform * from private.snake_sessions;raise exception 'TEST: private games readable';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000c01',true);
select set_config('test.setting_request',gen_random_uuid()::text,true);
select public.admin_game_settings(6,current_setting('test.setting_request')::uuid);
select public.admin_game_settings(6,current_setting('test.setting_request')::uuid);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000c02',true);
select set_config('test.batch',gen_random_uuid()::text,true);
do $$declare r jsonb;cash numeric;begin
 select balance into cash from public.wallets where user_id=auth.uid();
 r:=public.casino_plinko_batch(2,3,current_setting('test.batch')::uuid);
 if jsonb_array_length(r)<>3 or (select count(*) from public.casino_rounds where user_id=auth.uid())<>3 then raise exception 'TEST: wrong batch size';end if;
 perform public.casino_plinko_batch(2,3,current_setting('test.batch')::uuid);
 if (select count(*) from public.casino_rounds where user_id=auth.uid())<>3 or (public.casino_state()->>'remaining')::numeric<>0 or (public.casino_state()->>'daily_limit')::integer<>6 then raise exception 'TEST: batch duplicate or daily budget';end if;
 begin perform public.casino_plinko_batch(1,1,gen_random_uuid());raise exception 'TEST: exceeded daily budget';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Daily games budget reached' then raise;end if;end;
 begin perform public.casino_plinko_batch(2,2,current_setting('test.batch')::uuid);raise exception 'TEST: changed nonce spec';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Request ID already used' then raise;end if;end;
end $$;
reset role;
update private.game_settings set casino_daily_limit=7 where id=1;
set local role authenticated;
do $$declare cash numeric;begin
 select balance into cash from public.wallets where user_id=auth.uid();
 begin perform public.casino_plinko_batch(1,2,gen_random_uuid());raise exception 'TEST: partial batch committed';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Daily games budget reached' then raise;end if;end;
 if (select count(*) from public.casino_rounds where user_id=auth.uid())<>3 or (select balance from public.wallets where user_id=auth.uid())<>cash then raise exception 'TEST: failed batch charged';end if;
end $$;
select set_config('test.snake_start',gen_random_uuid()::text,true);
select set_config('test.snake_id',(public.snake_start(false,current_setting('test.snake_start')::uuid)->'session'->>'id'),true);
do $$begin if public.snake_start(false,current_setting('test.snake_start')::uuid)->'session'->>'id'<>current_setting('test.snake_id') then raise exception 'TEST: start duplicate';end if;end $$;
reset role;
update private.snake_sessions set state='{"body":[210,209,208],"direction":1,"apple":211,"seed":17,"score":0,"steps":0,"over":false}',created_at=clock_timestamp()-interval '2 seconds' where id=current_setting('test.snake_id')::uuid;
select set_config('test.snake_cash',(select balance::text from public.wallets where user_id='00000000-0000-4000-8000-000000000c02'),true);
set local role authenticated;
select set_config('test.snake_move',gen_random_uuid()::text,true);
do $$declare r jsonb;begin
 r:=public.snake_step(current_setting('test.snake_id')::uuid,0,array[1],current_setting('test.snake_move')::uuid);
 if (r->>'earned')::integer<>1 or (r->'session'->'state'->>'score')::integer<>1 or (select balance from public.wallets where user_id=auth.uid())<>current_setting('test.snake_cash')::numeric+1 then raise exception 'TEST: apple reward';end if;
 perform public.snake_step(current_setting('test.snake_id')::uuid,0,array[1],current_setting('test.snake_move')::uuid);
 if (select balance from public.wallets where user_id=auth.uid())<>current_setting('test.snake_cash')::numeric+1 then raise exception 'TEST: replay minted reward';end if;
 begin perform public.snake_step(current_setting('test.snake_id')::uuid,0,array[1],gen_random_uuid());raise exception 'TEST: stale accepted';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'This game changed%' then raise;end if;end;
 begin perform public.snake_step(current_setting('test.snake_id')::uuid,1,array[null::integer],gen_random_uuid());raise exception 'TEST: null direction';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Invalid Snake move' then raise;end if;end;
end $$;
reset role;
update private.snake_daily set earned=99 where user_id='00000000-0000-4000-8000-000000000c02';
update private.snake_sessions set state=jsonb_set(state,'{apple}','212') where id=current_setting('test.snake_id')::uuid;
set local role authenticated;
do $$declare r jsonb;begin r:=public.snake_step(current_setting('test.snake_id')::uuid,1,array[1],gen_random_uuid());if (r->>'earned')::integer<>100 or (r->>'remaining')::integer<>0 then raise exception 'TEST: daily cap';end if;end $$;
reset role;
update private.snake_sessions set state=jsonb_set(state,'{apple}','213') where id=current_setting('test.snake_id')::uuid;
set local role authenticated;
do $$declare r jsonb;begin r:=public.snake_step(current_setting('test.snake_id')::uuid,2,array[1],gen_random_uuid());if (r->>'earned')::integer<>100 or (r->'session'->'state'->>'score')::integer<>3 or (select balance from public.wallets where user_id=auth.uid())<>current_setting('test.snake_cash')::numeric+2 then raise exception 'TEST: cap bypass or cannot play past cap';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000c03',true);
do $$begin
 begin perform public.snake_step(current_setting('test.snake_id')::uuid,3,array[1],gen_random_uuid());raise exception 'TEST: other player game';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm<>'Snake game not found' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000c02',true);
select set_config('test.snake_id',(public.snake_start(true,gen_random_uuid())->'session'->>'id'),true);
do $$begin
 if (public.snake_state()->>'remaining')::integer<>0 then raise exception 'TEST: restart cleared daily cap';end if;
 begin perform public.snake_step(current_setting('test.snake_id')::uuid,0,array_fill(1,array[40]),gen_random_uuid());raise exception 'TEST: accelerated game';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Moves arrived too quickly%' then raise;end if;end;
end $$;
reset role;
update public.profiles set frozen_until=clock_timestamp()+interval '1 minute' where id='00000000-0000-4000-8000-000000000c02';
set local role authenticated;
do $$begin begin perform public.snake_start(false,gen_random_uuid());raise exception 'TEST: frozen game';exception when others then if sqlerrm like 'TEST:%' then raise;end if;if sqlerrm not like 'Account timed out%' then raise;end if;end;end $$;
reset role;
do $$declare state jsonb;begin
 state:=private.snake_move('{"body":[19,18,17],"direction":1,"apple":25,"seed":17,"score":0,"steps":0,"over":false}',1);
 if not (state->>'over')::boolean then raise exception 'TEST: row wrapped';end if;
 state:=private.snake_move('{"body":[210,209,208],"direction":1,"apple":211,"seed":17,"score":0,"steps":0,"over":false}',3);
 if (state->>'direction')::integer<>1 or (state->>'score')::integer<>1 then raise exception 'TEST: reverse';end if;
 if (select sum(balance) from private.credit_accounts)<>current_setting('test.supply')::numeric then raise exception 'TEST: supply not conserved';end if;
 if has_function_privilege('anon','public.snake_step(uuid,integer,integer[],uuid)','execute') or has_function_privilege('authenticated','private.snake_move(jsonb,integer)','execute') then raise exception 'TEST: permissions';end if;
end $$;
set constraints all immediate;
select 'PASS: atomic Plinko batches, configurable casino budget, server-replayed Snake, one-time capped rewards, ownership, timeout, timing, and conserved treasury' result;
rollback;
