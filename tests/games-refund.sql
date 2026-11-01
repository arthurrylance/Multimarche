-- Narrow rollback-only refund test: one synthetic member/hand, no admin role or economy reset.
begin;
insert into private.invites values(encode(extensions.digest('game-refund-fixture','sha256'),'hex'),1,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values('00000000-0000-4000-8000-000000000b01','game_refund_fixture@members.multimarche.invalid','{"username":"game_refund_fixture","invite":"game-refund-fixture"}');
do $$declare rid uuid;before_cash numeric;before_supply numeric;begin
 select balance into before_cash from public.wallets where user_id='00000000-0000-4000-8000-000000000b01';select total_supply into before_supply from private.economy;
 insert into public.casino_rounds(user_id,game,stake,max_payout,economy_round,state) values('00000000-0000-4000-8000-000000000b01','blackjack',5,12.5,(select reset_version from private.economy),'{"player":[0,20],"dealer":[36,null],"player_total":17}') returning id into rid;
 update public.wallets set balance=balance-5 where user_id='00000000-0000-4000-8000-000000000b01';insert into public.ledger(user_id,amount,reason) values('00000000-0000-4000-8000-000000000b01',-5,'Games: blackjack stake');
 insert into private.credit_accounts values('casino:'||rid,0);perform private.transfer('treasury','casino:'||rid,12.5,'Games payout reserve',null);
 perform private.casino_finish(rid,'void',5,'{"player":[0,20],"dealer":[36,null],"player_total":17}');
 perform private.casino_finish(rid,'void',5,'{}');
 if (select payout from public.casino_rounds where id=rid)<>5 or (select status from public.casino_rounds where id=rid)<>'void' or (select balance from private.credit_accounts where id='casino:'||rid)<>0 or (select balance from public.wallets where user_id='00000000-0000-4000-8000-000000000b01')<>before_cash then raise exception 'Refund or duplicate-finish guard failed';end if;
 if (select sum(balance) from private.credit_accounts)<>before_supply then raise exception 'Supply changed';end if;
end $$;
set constraints all immediate;
select 'PASS: isolated hand refunded exactly once, escrow released, supply conserved' result;
rollback;
