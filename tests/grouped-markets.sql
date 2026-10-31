-- Rollback-only fixtures; no real group, trade, user or balance is changed.
begin;
insert into private.invites values(encode(extensions.digest('group-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000001011','group_admin@members.multimarche.invalid','{"username":"group_admin","invite":"group-test-only"}'),
('00000000-0000-4000-8000-000000001012','group_a@members.multimarche.invalid','{"username":"group_a","invite":"group-test-only"}'),
('00000000-0000-4000-8000-000000001013','group_b@members.multimarche.invalid','{"username":"group_b","invite":"group-test-only"}'),
('00000000-0000-4000-8000-000000001014','group_c@members.multimarche.invalid','{"username":"group_c","invite":"group-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000001011');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001011',true);
select set_config('test.options','[{"label":"Says etcetera","yes":"Says the exact phrase"},{"label":"Mentions homework"}]',true);
select set_config('test.close',(now()+interval '1 hour')::text,true);
select set_config('test.group_amm',public.create_market_group('Physics class',current_setting('test.options')::jsonb,current_setting('test.close')::timestamptz,2,true,'Count','amm','00000000-0000-4000-8000-000000001021')::text,true);
select set_config('test.a',(current_setting('test.group_amm')::jsonb->'market_ids'->>0),true);
select set_config('test.b',(current_setting('test.group_amm')::jsonb->'market_ids'->>1),true);
do $$declare before_count integer;repeat_result jsonb;
begin
 select count(*) into before_count from public.markets;
 repeat_result:=public.create_market_group('Physics class',current_setting('test.options')::jsonb,current_setting('test.close')::timestamptz,2,true,'Count','amm','00000000-0000-4000-8000-000000001021');
 if repeat_result<>current_setting('test.group_amm')::jsonb or (select count(*) from public.markets)<>before_count then raise exception 'Creation retry duplicated markets';end if;
 if (select group_id from public.markets where id=current_setting('test.a')::uuid)<>(current_setting('test.group_amm')::jsonb->>'group_id')::uuid then raise exception 'Group identity missing';end if;
 if (select yes_rule from public.markets where id=current_setting('test.a')::uuid)<>'Says the exact phrase' or nullif((select no_rule from public.markets where id=current_setting('test.b')::uuid),'') is null then raise exception 'Custom/default meanings missing';end if;
 if (select count(*) from public.markets where group_id=(current_setting('test.group_amm')::jsonb->>'group_id')::uuid and execution_model='amm' and counter_enabled and closes_at=current_setting('test.close')::timestamptz and required_verifications=2)<>2 then raise exception 'Shared creation settings not inherited';end if;
 begin perform public.create_market_group('Changed',current_setting('test.options')::jsonb,current_setting('test.close')::timestamptz,2,true,'Count','amm','00000000-0000-4000-8000-000000001021');raise exception 'TEST FAILED nonce conflict';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.create_market_group('Bad','[{"label":"Same"},{"label":"same "}]',now()+interval '1 hour',2,false,'Count','amm',gen_random_uuid());raise exception 'TEST FAILED duplicate labels';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform public.create_market_group('Bad','[{"label":"Only one"}]',now()+interval '1 hour',2,false,'Count','clob',gen_random_uuid());raise exception 'TEST FAILED one option';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin insert into public.market_groups(creator_id,title,request_id,creation_hash) values(auth.uid(),'Bypass',gen_random_uuid(),'x');raise exception 'TEST FAILED direct group write';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
do $$begin begin perform public.create_market_group('Physics class',current_setting('test.options')::jsonb,current_setting('test.close')::timestamptz,2,true,'Count','amm','00000000-0000-4000-8000-000000001021');raise exception 'TEST FAILED reused another account nonce';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
select public.trade(current_setting('test.a')::uuid,'yes','buy',10,100,gen_random_uuid());
do $$begin if (select probability from public.markets where id=current_setting('test.b')::uuid)<>.5 or (select q_yes from public.markets where id=current_setting('test.b')::uuid)<>0 then raise exception 'Trading affected a sibling';end if;end $$;
select public.trade(current_setting('test.b')::uuid,'yes','buy',12,100,gen_random_uuid());
select public.change_counter(current_setting('test.a')::uuid,1,gen_random_uuid());
do $$begin if (select counter_value from public.markets where id=current_setting('test.b')::uuid)<>0 then raise exception 'Counters leaked between options';end if;end $$;
select public.resolve_market(current_setting('test.a')::uuid,'yes','Observed');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001013',true);
select public.resolve_market(current_setting('test.a')::uuid,'yes','Confirmed');
do $$begin if (select status from public.markets where id=current_setting('test.b')::uuid)<>'open' then raise exception 'Resolving one froze a sibling';end if;end $$;
select public.resolve_market(current_setting('test.b')::uuid,'yes','Also observed');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
select public.resolve_market(current_setting('test.b')::uuid,'yes','Confirmed');
-- Both independent options can win Yes.
do $$begin if (select count(*) from public.markets where id in(current_setting('test.a')::uuid,current_setting('test.b')::uuid) and outcome='yes' and status='resolved')<>2 then raise exception 'Options treated as mutually exclusive';end if;end $$;
reset role;
select set_config('test.book_treasury',(select balance::text from private.credit_accounts where id='treasury'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001011',true);
select set_config('test.group_book',public.create_market_group('Next class','[{"label":"X"},{"label":"Y"},{"label":"Z"}]',now()+interval '1 hour',2,false,'Count','clob',gen_random_uuid())::text,true);
select set_config('test.x',(current_setting('test.group_book')::jsonb->'market_ids'->>0),true);
select set_config('test.y',(current_setting('test.group_book')::jsonb->'market_ids'->>1),true);
select set_config('test.z',(current_setting('test.group_book')::jsonb->'market_ids'->>2),true);
-- A late funding failure must roll back the parent, earlier children and their treasury seeds.
do $$declare before_groups integer;before_markets integer;treasury numeric;
begin
 select count(*) into before_groups from public.market_groups;select count(*) into before_markets from public.markets;
 begin
  select (public.economy_status()->>'treasury')::numeric into treasury;
  perform public.admin_credit(auth.uid(),treasury-300,'Fixture funding test',gen_random_uuid());
  begin perform public.create_market_group('Insufficient second reserve','[{"label":"One"},{"label":"Two"}]',now()+interval '1 hour',2,false,'Count','amm',gen_random_uuid());raise exception 'TEST FAILED unfunded creation';exception when others then if sqlerrm<>'Insufficient funded reserves' then raise;end if;end;
  if (select count(*) from public.market_groups)<>before_groups or (select count(*) from public.markets)<>before_markets then raise exception 'Partial group survived failure';end if;
  raise exception 'ROLLBACK_DRAIN';
 exception when others then if sqlerrm<>'ROLLBACK_DRAIN' then raise;end if;
 end;
end $$;
select public.admin_market(current_setting('test.z')::uuid,'edit','{"title":"New option Z"}','Rename option');
do $$begin if (select option_label from public.markets where id=current_setting('test.z')::uuid)<>'New option Z' or (select title from public.markets where id=current_setting('test.z')::uuid)<>'Next class · New option Z' then raise exception 'Admin edit left stale option label';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
select public.place_order(current_setting('test.x')::uuid,'yes','buy',.6,10,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001013',true);
select public.place_order(current_setting('test.y')::uuid,'no','buy',.4,10,'GTC',null,gen_random_uuid());
do $$begin if exists(select 1 from public.order_fills where market_id in(current_setting('test.x')::uuid,current_setting('test.y')::uuid)) then raise exception 'Orders matched across sibling markets';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001014',true);
select public.place_order(current_setting('test.x')::uuid,'no','buy',.4,10,'FOK',null,gen_random_uuid());
select public.place_order(current_setting('test.y')::uuid,'yes','buy',.6,10,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
select public.resolve_market(current_setting('test.x')::uuid,'yes','Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001013',true);
select public.resolve_market(current_setting('test.x')::uuid,'no','No');
do $$begin if (select status from public.markets where id=current_setting('test.y')::uuid)<>'open' then raise exception 'Dispute froze siblings';end if;end $$;
select public.resolve_market(current_setting('test.y')::uuid,'no','No');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
select public.resolve_market(current_setting('test.y')::uuid,'no','Confirmed');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001014',true);
select public.resolve_market(current_setting('test.x')::uuid,'yes','Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001013',true);
select public.resolve_market(current_setting('test.x')::uuid,'yes','Changed');
select public.resolve_market(current_setting('test.z')::uuid,'void','Unclear');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001012',true);
select public.resolve_market(current_setting('test.z')::uuid,'void','Confirmed');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001011',true);
select public.admin_history(current_setting('test.x')::uuid,true);
select public.admin_history(current_setting('test.y')::uuid,true);
select public.admin_history(current_setting('test.z')::uuid,true);
select public.admin_timeout('00000000-0000-4000-8000-000000001014',15);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001014',true);
do $$begin begin perform public.create_market_group('Frozen','[{"label":"A"},{"label":"B"}]',now()+interval '1 hour',2,false,'Count','clob',gen_random_uuid());raise exception 'TEST FAILED frozen creation';exception when others then if sqlerrm not like 'Account timed out%' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001013',true);
do $$begin if exists(select 1 from public.market_groups where id=(current_setting('test.group_book')::jsonb->>'group_id')::uuid) then raise exception 'Hidden child history leaked its parent';end if;end $$;
set local role anon;
do $$begin begin perform * from public.market_groups;raise exception 'TEST FAILED guest metadata';exception when insufficient_privilege then null;end;begin perform public.create_market_group('Guest','[{"label":"A"},{"label":"B"}]',now()+interval '1 hour',2,false,'Count','clob',gen_random_uuid());raise exception 'TEST FAILED guest creation';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if (select balance from private.credit_accounts where id='treasury')<>current_setting('test.book_treasury')::numeric then raise exception 'Book grouping changed treasury';end if;
 if exists(select 1 from private.credit_accounts where id in('market:'||current_setting('test.x'),'market:'||current_setting('test.y'),'market:'||current_setting('test.z')) and balance<>0) then raise exception 'Book collateral not fully paid';end if;
 if (select sum(amount) from public.ledger where market_id in(current_setting('test.a')::uuid,current_setting('test.b')::uuid) and reason='Settlement: yes')<>22 then raise exception 'Multiple Yes payouts incorrect';end if;
 begin update public.markets set group_id=(current_setting('test.group_amm')::jsonb->>'group_id')::uuid where id=current_setting('test.z')::uuid;raise exception 'TEST FAILED moved child';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000001011',true);
do $$begin if not public.verify_audit() then raise exception 'Audit invalid';end if;end $$;
reset role;
set constraints all immediate;
select 'PASS: atomic/idempotent grouped creation, both pricing models, shared settings, independent prices/counters/orders/results/payouts, multiple Yes winners, dispute isolation, late-failure rollback, group identity and label edits, private metadata, timeout/guest denial, exact collateral and audit conservation' result;
rollback;
