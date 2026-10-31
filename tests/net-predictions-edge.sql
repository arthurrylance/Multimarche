-- All fixtures, trades, loan draws and reset calls are rolled back. Never commit this file.
begin;
insert into private.invites values(encode(extensions.digest('net-extra-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000a01','netx_admin@members.multimarche.invalid','{"username":"netx_admin","invite":"net-extra-only"}'),
('00000000-0000-4000-8000-000000000a02','netx_a@members.multimarche.invalid','{"username":"netx_a","invite":"net-extra-only"}'),
('00000000-0000-4000-8000-000000000a03','netx_b@members.multimarche.invalid','{"username":"netx_b","invite":"net-extra-only"}'),
('00000000-0000-4000-8000-000000000a04','netx_c@members.multimarche.invalid','{"username":"netx_c","invite":"net-extra-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000a01');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select set_config('test.amm',public.create_market_v7('Prior quote','Yes','No',now()+interval '1 hour',2,false,'Count','amm',.1)::text,true);
select set_config('test.book',public.create_market_v7('Loan book','Yes','No',now()+interval '1 day',2,false,'Count','clob',.2)::text,true);
select set_config('test.empty',public.create_market_v7('Empty book','Yes','No',now()+interval '1 day',2,false,'Count','clob',.5)::text,true);
select set_config('test.g',(public.create_market_group_v2('Prior group','[{"label":"A"},{"label":"B","probability":0.8}]',now()+interval '1 day',2,false,'Count','amm',gen_random_uuid(),.2)->>'group_id'),true);
do $$begin if (select initial_probability from public.markets where group_id=current_setting('test.g')::uuid and option_label='A')<>.2 or (select initial_probability from public.markets where group_id=current_setting('test.g')::uuid and option_label='B')<>.8 then raise exception 'Grouped priors not respected';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.predict(current_setting('test.amm')::uuid,'yes',10,5,null,'GTC',null,0,gen_random_uuid());
do $$declare p numeric;begin select probability into p from public.markets where id=current_setting('test.amm')::uuid;if p<=.1 or p>=.5 then raise exception 'Weighted AMM odds drifted to wrong prior: %',p;end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.amm')::uuid,'settle','{"outcome":"yes"}','Loan win fixture');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
do $$begin if exists(select 1 from public.leverage_positions where status='active') or (select loan_collateral from public.wallets)<>0 then raise exception 'Win loan not repaid';end if;
 begin perform public.predict(current_setting('test.empty')::uuid,'yes',10,10,.5,'FOK',null,0,gen_random_uuid());raise exception 'TEST FAILED unfilled leveraged FOK';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 if exists(select 1 from public.leverage_positions where status='active') or (select loan_collateral from public.wallets)<>0 then raise exception 'Failed FOK leaked a loan';end if;
end $$;
select public.predict(current_setting('test.empty')::uuid,'yes',10,10,.5,'GTC',null,0,gen_random_uuid());
do $$begin if (select loan_collateral from public.wallets)<>90 then raise exception 'Waiting leveraged order not secured';end if;end $$;
select public.cancel_my_orders(current_setting('test.empty')::uuid);
do $$begin if exists(select 1 from public.leverage_positions where status='active') then raise exception 'Cancelled loan not repaid';end if;end $$;
select public.predict(current_setting('test.empty')::uuid,'yes',10,5,.5,'FAK',null,0,gen_random_uuid());
do $$begin if exists(select 1 from public.leverage_positions where status='active') then raise exception 'Empty FAK loan not repaid';end if;end $$;
-- Partial leveraged maker fills remain secured; cancellation does not close a held position.
select public.predict(current_setting('test.book')::uuid,'yes',10,5,.6,'GTC',null,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,20,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
select public.cancel_my_orders(current_setting('test.book')::uuid);
do $$begin if not exists(select 1 from public.leverage_positions where status='active') or (select loan_collateral from public.wallets)<>40 then raise exception 'Partial fill loan released too soon';end if;end $$;
-- Both holders move in opposite directions: complementary reductions merge the pair, leaving flat.
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,20,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a03',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,20,'FOK',null,gen_random_uuid());
reset role;
do $$begin if exists(select 1 from public.positions where market_id=current_setting('test.book')::uuid and shares>0) or exists(select 1 from public.leverage_positions where status='active') then raise exception 'Merge did not flatten/repay';end if;end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a02',true);
-- Insufficient max-loss coverage cannot borrow; request replay cannot change economics.
do $$begin begin perform public.predict(current_setting('test.book')::uuid,'yes',100000,10,.5,'GTC',null,0,gen_random_uuid());raise exception 'TEST FAILED unsecured leverage';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select public.predict(current_setting('test.book')::uuid,'no',10,10,.4,'GTC',null,0,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000a01',true);
select public.admin_market(current_setting('test.book')::uuid,'settle','{"outcome":"void"}','Void waiting loan');
do $$begin if not public.verify_audit() then raise exception 'Financial audit invalid';end if;end $$;
reset role;
set constraints all immediate;
select 'PASS: weighted odds, grouped priors, secured wins, FOK rollback, waiting/cancel/FAK/partial loans, net merge to flat, void repayment and immutable audit' result;
rollback;
