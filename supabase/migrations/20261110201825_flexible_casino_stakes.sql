-- All casino games use the existing owned-credit and daily budget checks.
alter table public.casino_rounds add constraint casino_rounds_whole_stake_check
 check (stake>=1 and stake=trunc(stake) and stake::text not in('NaN','Infinity','-Infinity')) not valid;
alter table public.casino_rounds validate constraint casino_rounds_whole_stake_check;
alter table public.casino_rounds drop constraint casino_rounds_stake_check;

create or replace function private.casino_start(p_game text,p_stake numeric,p_choice text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();spec jsonb;prior private.casino_requests;r public.casino_rounds;round_id bigint;spent numeric;max_return numeric;deck integer[];player integer[];dealer integer[];i integer;j integer;swap integer;number integer;slot integer:=0;path jsonb:='[]';multiplier numeric;view jsonb;ps integer;ds integer;
begin
 perform pg_advisory_xact_lock(84271001);spec:=jsonb_build_object('kind','start','game',p_game,'stake',p_stake,'choice',p_choice);
 select * into prior from private.casino_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return(select to_jsonb(cr) from public.casino_rounds cr where id=(prior.result->>'id')::uuid);end if;
 if p_request is null or p_game is null or p_game not in('blackjack','roulette','plinko') or p_stake is null or p_stake::text in('NaN','Infinity','-Infinity') or p_stake<1 or p_stake<>trunc(p_stake) then raise exception 'Choose a whole-credit stake of at least 1';end if;
 if p_game='roulette' then perform private.roulette_multiplier(p_choice,0);end if;
 if p_game<>'roulette' and p_choice is not null then raise exception 'This game does not use a roulette choice';end if;
 if p_game='blackjack' and exists(select 1 from public.casino_rounds where user_id=uid and game='blackjack' and status='active') then raise exception 'Finish your current blackjack hand first';end if;
 select reset_version into round_id from private.economy where id=1;
 select coalesce(sum(stake),0) into spent from public.casino_rounds where user_id=uid and economy_round=round_id and created_at>=date_trunc('day',now() at time zone 'Europe/Zurich') at time zone 'Europe/Zurich';
 if spent+p_stake>(select casino_daily_limit from private.game_settings where id=1) then raise exception 'Daily games budget reached';end if;
 if not exists(select 1 from public.wallets where user_id=uid and balance-reserved_balance-loan_collateral>=p_stake) then raise exception 'Insufficient available owned credits';end if;
 max_return:=p_stake*case p_game when 'blackjack' then 2.5 when 'roulette' then case when p_choice in('red','black','odd','even') then 2 else 36 end else 8 end;
 insert into public.casino_rounds(user_id,game,stake,max_payout,economy_round) values(uid,p_game,p_stake,max_return,round_id) returning * into r;
 update public.wallets set balance=balance-p_stake where user_id=uid;insert into public.ledger(user_id,amount,reason) values(uid,-p_stake,'Games: '||p_game||' stake');
 insert into private.credit_accounts(id,balance) values('casino:'||r.id,0);perform private.transfer('treasury','casino:'||r.id,max_return,'Games payout reserve',null);
 if p_game='roulette' then
  number:=private.casino_random(37);multiplier:=private.roulette_multiplier(p_choice,number);
  perform private.casino_finish(r.id,case when multiplier>0 then 'win' else 'loss' end,p_stake*multiplier,jsonb_build_object('number',number,'choice',p_choice));
 elsif p_game='plinko' then
  for i in 1..8 loop j:=private.casino_random(2);slot:=slot+j;path:=path||jsonb_build_array(j);end loop;
  multiplier:=(array[8,3,1.5,.7,.4,.7,1.5,3,8]::numeric[])[slot+1];
  perform private.casino_finish(r.id,case when multiplier>1 then 'win' when multiplier=1 then 'push' else 'loss' end,p_stake*multiplier,jsonb_build_object('path',path,'slot',slot,'multiplier',multiplier));
 else
  select array_agg(n order by n) into deck from generate_series(0,51) n;
  for i in reverse 52..2 loop j:=private.casino_random(i)+1;swap:=deck[i];deck[i]:=deck[j];deck[j]:=swap;end loop;
  player:=array[deck[1],deck[3]];dealer:=array[deck[2],deck[4]];
  insert into private.casino_hands values(r.id,deck,player,dealer,5);ps:=private.blackjack_score(player);ds:=private.blackjack_score(dealer);
  if ps=21 or ds=21 then perform private.casino_finish(r.id,case when ps=21 and ds=21 then 'push' when ps=21 then 'blackjack' else 'loss' end,case when ps=21 and ds=21 then p_stake when ps=21 then p_stake*2.5 else 0 end,private.blackjack_view(r.id,true));
  else update public.casino_rounds set state=private.blackjack_view(r.id,false) where id=r.id;end if;
 end if;
 select * into r from public.casino_rounds where id=r.id;insert into private.casino_requests values(p_request,uid,spec,to_jsonb(r));return to_jsonb(r);
end $$;


revoke all on function private.casino_start(text,numeric,text,uuid) from public,anon,authenticated;
grant execute on function private.casino_start(text,numeric,text,uuid) to authenticated;
