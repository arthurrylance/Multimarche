-- Owner-run test. Fixture accounts, role changes, transfers and audit blocks roll back.
begin;
insert into private.invites values(encode(extensions.digest('v2-test-only','sha256'),'hex'),2,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000101','v2_admin_fixture@members.multimarche.invalid','{"username":"v2_admin_fixture","invite":"v2-test-only"}'),
('00000000-0000-4000-8000-000000000102','v2_member_fixture@members.multimarche.invalid','{"username":"v2_member_fixture","invite":"v2-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000101');
update auth.users set email='v2_renamed_fixture@members.multimarche.invalid',raw_user_meta_data='{"nickname":"Fixture Nickname","role":"admin"}' where id='00000000-0000-4000-8000-000000000102';
do $$begin
 if not exists(select 1 from public.profiles where id='00000000-0000-4000-8000-000000000102' and username='v2_renamed_fixture' and nickname='Fixture Nickname') then raise exception 'Profile and identity not synchronized';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000102',true);
do $$begin
 if public.is_admin() then raise exception 'User metadata granted admin';end if;
 begin perform public.admin_mint(100,'Forbidden issuance',gen_random_uuid());raise exception 'TEST FAILED non-admin issuance';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform private.trade_v1(gen_random_uuid(),'yes','buy',1,100,gen_random_uuid());raise exception 'TEST FAILED legacy trade bypass';exception when insufficient_privilege then null;end;
 begin update public.audit_blocks set hash=repeat('0',64);raise exception 'TEST FAILED audit edit';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select set_config('test.v2market',public.create_market_v2('Will the v2 economy test pass?','Yes when all test assertions pass; No otherwise.','Other',now()+interval '40 minutes',400)::text,true);
do $$declare m uuid:=current_setting('test.v2market')::uuid;before jsonb;after_state jsonb;
begin
 if not public.is_admin() then raise exception 'Admin role not detected';end if;
 before:=public.economy_status();
 perform public.admin_credit('00000000-0000-4000-8000-000000000102',100,'Private nickname should not go on chain','00000000-0000-4000-8000-000000000111');
 perform public.admin_credit('00000000-0000-4000-8000-000000000102',100,'Private nickname should not go on chain','00000000-0000-4000-8000-000000000111');
 after_state:=public.economy_status();
 if (after_state->>'total_supply')::numeric<>(before->>'total_supply')::numeric then raise exception 'Allocation minted credits';end if;
 if (after_state->>'treasury')::numeric<>(before->>'treasury')::numeric-100 then raise exception 'Allocation not idempotent';end if;
 if exists(select 1 from public.audit_blocks where payload like '%Private nickname%') then raise exception 'Private reason leaked';end if;
 perform public.admin_mint(250,'Explicit test issuance','00000000-0000-4000-8000-000000000112');
 perform public.admin_mint(250,'Explicit test issuance','00000000-0000-4000-8000-000000000112');
 if (public.economy_status()->>'total_supply')::numeric<>(before->>'total_supply')::numeric+250 then raise exception 'Mint supply incorrect';end if;
 perform public.trade(m,'yes','buy',100,100,gen_random_uuid());
 perform public.admin_market(m,'pause','{}','Test pause trading');
 begin perform public.trade(m,'yes','buy',1,100,gen_random_uuid());raise exception 'TEST FAILED paused trade';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.admin_market(m,'resume','{}','Test resume trading');
 perform public.trade(m,'yes','sell',25,0,gen_random_uuid());
 perform public.admin_market(m,'settle','{"outcome":"yes"}','Test audited admin settlement');
 if (select count(*) from public.ledger where market_id=m and reason='Settlement: yes')<>1 then raise exception 'Wrong settlement count';end if;
 if (select amount from public.ledger where market_id=m and reason='Settlement: yes')<>75 then raise exception 'Wrong settlement payout';end if;
 begin perform public.admin_market(m,'settle','{"outcome":"yes"}','Test double settlement');raise exception 'TEST FAILED duplicate settlement';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 perform public.admin_market(m,'archive','{}','Test archive settled market');
 if not public.verify_audit() then raise exception 'Invalid audit chain';end if;
end $$;
reset role;
do $$begin
 if exists(select 1 from private.credit_accounts a join public.markets m on a.id='market:'||m.id where m.id=current_setting('test.v2market')::uuid and a.balance<>0) then raise exception 'Unused reserve not released';end if;
 begin update public.audit_blocks set payload='{}' where seq=1;raise exception 'TEST FAILED owner audit modification';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set constraints all immediate;
select 'PASS: funded treasury, conservation, reserved payouts, allocation/issuance separation, idempotency, admin access, metadata spoof denial, profile sync, pause/resume, settlement, reserve release, immutable hash chain, privacy' as result;
rollback;
