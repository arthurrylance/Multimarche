-- Owner-run regression fixture: no live accounts, markets or funds survive this transaction.
begin;
insert into private.invites values(encode(extensions.digest('modes-test-only','sha256'),'hex'),4,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-4000-8000-000000000901','modes_admin@members.multimarche.invalid','{"username":"modes_admin","invite":"modes-test-only"}'),
('00000000-0000-4000-8000-000000000902','modes_a@members.multimarche.invalid','{"username":"modes_a","invite":"modes-test-only"}'),
('00000000-0000-4000-8000-000000000903','modes_b@members.multimarche.invalid','{"username":"modes_b","invite":"modes-test-only"}'),
('00000000-0000-4000-8000-000000000904','modes_c@members.multimarche.invalid','{"username":"modes_c","invite":"modes-test-only"}');
insert into private.admins values('00000000-0000-4000-8000-000000000901');
select set_config('test.supply',(select total_supply::text from private.economy),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000901',true);
select set_config('test.amm',public.create_market_v6('Automatic fixture','Yes','No',now()+interval '40 minutes',2,true,'Count','amm')::text,true);
select set_config('test.book',public.create_market_v6('Book fixture','Yes','No',now()+interval '1 day',2,false,'Count','clob')::text,true);
select set_config('test.empty',public.create_market_v6('Withdraw fixture','Yes','No',now()+interval '1 hour',2,false,'Count','clob')::text,true);
do $$begin
 if (select execution_model from public.markets where id=current_setting('test.amm')::uuid)<>'amm' or (select liquidity from public.markets where id=current_setting('test.amm')::uuid)<>400 or not (select counter_enabled from public.markets where id=current_setting('test.amm')::uuid) then raise exception 'Automatic creation failed';end if;
 if (select execution_model from public.markets where id=current_setting('test.book')::uuid)<>'clob' then raise exception 'Order book selection ignored';end if;
 begin perform public.create_market_v6('Bad','Yes','No',now()+interval '1 hour',2,false,'Count','other');raise exception 'TEST FAILED unknown model';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
 begin perform private.reconcile_resolution(current_setting('test.book')::uuid);raise exception 'TEST FAILED exposed settlement helper';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
select public.trade(current_setting('test.amm')::uuid,'yes','buy',10,100,gen_random_uuid());
do $$begin if (select probability from public.markets where id=current_setting('test.amm')::uuid)<=.5 then raise exception 'Automatic odds did not move';end if;end $$;
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.6,10,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000903',true);
select public.place_order(current_setting('test.book')::uuid,'no','buy',.4,10,'FOK',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000904',true);
select public.place_order(current_setting('test.book')::uuid,'yes','buy',.2,5,'GTC',null,gen_random_uuid());
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
select public.resolve_market(current_setting('test.book')::uuid,'yes','Observed Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000903',true);
do $$begin
 if public.resolve_market(current_setting('test.book')::uuid,'no','No, it did not')<>'disputed' then raise exception 'Opposition not recorded';end if;
 if not (select resolution_disputed from public.markets where id=current_setting('test.book')::uuid) then raise exception 'Dispute flag missing';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000904',true);
do $$begin
 if (select reserved_balance from public.wallets)<>0 then raise exception 'Proposal left open orders reserved';end if;
 if public.resolve_market(current_setting('test.book')::uuid,'yes','Second Yes')<>'disputed' then raise exception 'Threshold overrode active disagreement';end if;
 if (select status from public.markets where id=current_setting('test.book')::uuid)<>'proposed' then raise exception 'Disputed market paid';end if;
 begin perform public.place_order(current_setting('test.book')::uuid,'yes','buy',.5,1,'GTC',null,gen_random_uuid());raise exception 'TEST FAILED traded during dispute';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000903',true);
do $$begin
 if public.resolve_market(current_setting('test.book')::uuid,'yes','Changing my observation')<>'resolved' then raise exception 'Consensus after vote change did not settle';end if;
 if (select count(*) from public.resolution_votes where market_id=current_setting('test.book')::uuid and user_id=auth.uid())<>1 then raise exception 'Vote change duplicated voter';end if;
 begin perform public.resolve_market(current_setting('test.book')::uuid,'no','Again');raise exception 'TEST FAILED changed settled outcome';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
-- Removing an opposing vote can settle the remaining consensus, once only.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
select public.resolve_market(current_setting('test.amm')::uuid,'yes','Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000903',true);
select public.resolve_market(current_setting('test.amm')::uuid,'no','No');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000904',true);
select public.resolve_market(current_setting('test.amm')::uuid,'yes','Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000903',true);
select public.withdraw_resolution(current_setting('test.amm')::uuid);
do $$begin if (select status from public.markets where id=current_setting('test.amm')::uuid)<>'resolved' then raise exception 'Withdrawal did not reconcile consensus';end if;end $$;
-- Withdrawing the only observation reopens, without removing an admin pause.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000901',true);
select public.admin_market(current_setting('test.empty')::uuid,'pause','{}','Fixture pause');
select public.resolve_market(current_setting('test.empty')::uuid,'yes','Early');
select public.withdraw_resolution(current_setting('test.empty')::uuid);
do $$begin if (select status from public.markets where id=current_setting('test.empty')::uuid)<>'open' or not (select paused from public.markets where id=current_setting('test.empty')::uuid) then raise exception 'Withdrawal lost manual pause';end if;end $$;
select public.resolve_market(current_setting('test.empty')::uuid,'yes','Yes');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
select public.resolve_market(current_setting('test.empty')::uuid,'void','Unclear');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000901',true);
select public.admin_market(current_setting('test.empty')::uuid,'settle','{"outcome":"no"}','Override disputed fixture');
do $$begin if (select resolution_disputed from public.markets where id=current_setting('test.empty')::uuid) then raise exception 'Admin override left dispute flag';end if;end $$;
-- Profile rerolls are own-account only, persistent, and always choose a different colour.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
do $$declare old_color text;new_color text;i integer;
begin
 old_color:='cyan';
 for i in 1..20 loop
  new_color:=public.randomize_avatar();
  if new_color=old_color or (select avatar_color from public.profiles where id=auth.uid())<>new_color then raise exception 'Avatar reroll did not persist a different colour';end if;
  old_color:=new_color;
 end loop;
 if (select avatar_color from public.profiles where id='00000000-0000-4000-8000-000000000903') is not null then raise exception 'Reroll changed another user';end if;
 begin update public.profiles set avatar_color='red' where id='00000000-0000-4000-8000-000000000903';raise exception 'TEST FAILED direct profile write';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000901',true);
select public.admin_timeout('00000000-0000-4000-8000-000000000902',15);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000902',true);
do $$begin
 begin perform public.create_market_v6('Frozen','Yes','No',now()+interval '1 hour',2,false,'Count','amm');raise exception 'TEST FAILED frozen creation';exception when others then if sqlerrm not like 'Account timed out%' then raise;end if;end;
 begin perform public.resolve_market(current_setting('test.book')::uuid,'no','Frozen');raise exception 'TEST FAILED frozen result';exception when others then if sqlerrm not like 'Account timed out%' then raise;end if;end;
 perform public.randomize_avatar(); -- Profile editing remains available during a timeout.
end $$;
reset role;
update public.profiles set active=false where id='00000000-0000-4000-8000-000000000902';
set local role authenticated;
do $$begin begin perform public.randomize_avatar();raise exception 'TEST FAILED stale removed-member reroll';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;end $$;
set local role anon;
do $$begin begin perform public.randomize_avatar();raise exception 'TEST FAILED guest reroll';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if (select balance from private.credit_accounts where id='market:'||current_setting('test.book'))<>0 then raise exception 'Book collateral remained';end if;
 if (select sum(amount) from public.ledger where market_id=current_setting('test.book')::uuid and reason='Settlement: yes')<>10 then raise exception 'Book payout incorrect';end if;
 if (select sum(amount) from public.ledger where market_id=current_setting('test.amm')::uuid and reason='Settlement: yes')<>10 then raise exception 'Automatic payout incorrect';end if;
 if (select total_supply from private.economy)<>current_setting('test.supply')::numeric then raise exception 'Unexpected issuance';end if;
 begin update public.markets set execution_model='clob' where id=current_setting('test.amm')::uuid;raise exception 'TEST FAILED model conversion';exception when others then if sqlerrm like 'TEST FAILED%' then raise;end if;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000901',true);
do $$begin if not public.verify_audit() then raise exception 'Audit invalid';end if;end $$;
reset role;
set constraints all immediate;
select 'PASS: Automatic and order book creation, instant automatic odds, funded matched book, disagreement blocks payouts, vote changes/withdrawal reconcile consensus, closed-state guards, admin override, immutable models, own persistent avatar rerolls, guest denial, supply and audit conservation' result;
rollback;
