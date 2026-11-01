create table public.casino_rounds(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),game text not null check(game in('blackjack','roulette','plinko')),stake numeric not null check(stake between 1 and 5 and stake=trunc(stake)),max_payout numeric not null check(max_payout>0),payout numeric not null default 0 check(payout>=0 and payout<=max_payout),status text not null default 'active' check(status in('active','settled','void')),state jsonb not null default '{}',version integer not null default 1,economy_round bigint not null,created_at timestamptz not null default now(),finished_at timestamptz);
create index casino_user_round_idx on public.casino_rounds(user_id,economy_round,created_at desc);
create unique index casino_active_blackjack on public.casino_rounds(user_id) where game='blackjack' and status='active';
alter table public.casino_rounds enable row level security;
create policy own_casino_rounds on public.casino_rounds for select to authenticated using(user_id=(select auth.uid()) and (select private.is_member()));
revoke all on public.casino_rounds from public,anon,authenticated;grant select on public.casino_rounds to authenticated;
alter publication supabase_realtime add table public.casino_rounds;
create table private.casino_hands(round_id uuid primary key references public.casino_rounds(id),deck integer[] not null,player integer[] not null,dealer integer[] not null,next_card integer not null);
create table private.casino_requests(request_id uuid primary key,user_id uuid not null references public.profiles(id),spec jsonb not null,result jsonb not null);
create index casino_request_user_idx on private.casino_requests(user_id);
alter table private.casino_hands enable row level security;alter table private.casino_requests enable row level security;
revoke all on private.casino_hands,private.casino_requests from public,anon,authenticated;

-- Rejection sampling avoids modulo bias. Only server-owned helpers can draw randomness.
create function private.casino_random(p_max integer) returns integer language plpgsql volatile security definer set search_path='' as $$
declare bytes bytea;n bigint;cutoff bigint;
begin
 if p_max<1 or p_max>1000000 then raise exception 'Invalid random range';end if;
 cutoff:=(4294967296::bigint/p_max)*p_max;
 loop bytes:=extensions.gen_random_bytes(4);n:=get_byte(bytes,0)::bigint*16777216+get_byte(bytes,1)::bigint*65536+get_byte(bytes,2)::bigint*256+get_byte(bytes,3);exit when n<cutoff;end loop;
 return (n%p_max)::integer;
end $$;
create function private.blackjack_score(p_cards integer[]) returns integer language plpgsql immutable set search_path='' as $$
declare card integer;rank integer;score integer:=0;aces integer:=0;
begin foreach card in array p_cards loop rank:=card/4;if rank=0 then score:=score+11;aces:=aces+1;else score:=score+least(10,rank+1);end if;end loop;while score>21 and aces>0 loop score:=score-10;aces:=aces-1;end loop;return score;end $$;
create function private.blackjack_view(p_round uuid,p_reveal boolean) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('player',player,'dealer',case when p_reveal then to_jsonb(dealer) else jsonb_build_array(dealer[1],null) end,'player_total',private.blackjack_score(player),'dealer_total',case when p_reveal then private.blackjack_score(dealer) else null end) from private.casino_hands where round_id=p_round$$;
create function private.casino_finish(p_round uuid,p_outcome text,p_payout numeric,p_state jsonb) returns void language plpgsql security definer set search_path='' as $$
declare r public.casino_rounds;reserve numeric;
begin
 select * into r from public.casino_rounds where id=p_round for update;if not found or r.status<>'active' then return;end if;
 if p_payout is null or p_payout::text in('NaN','Infinity','-Infinity') or p_payout<0 or p_payout>r.max_payout then raise exception 'Invalid game payout';end if;
 select balance into reserve from private.credit_accounts where id='casino:'||r.id;
 perform private.transfer('casino:'||r.id,'treasury',reserve,'Games reserve release',null);
 if p_payout>0 then update public.wallets set balance=balance+p_payout where user_id=r.user_id;insert into public.ledger(user_id,amount,reason) values(r.user_id,p_payout,'Games: '||r.game||' '||p_outcome);end if;
 update public.casino_rounds set payout=p_payout,status=case when p_outcome='void' then 'void' else 'settled' end,state=p_state||jsonb_build_object('outcome',p_outcome),version=version+1,finished_at=clock_timestamp() where id=r.id;
end $$;
create function private.casino_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();round_id bigint;spent numeric;day_start timestamptz;
begin
 select reset_version into round_id from private.economy where id=1;day_start:=date_trunc('day',now() at time zone 'Europe/Zurich') at time zone 'Europe/Zurich';
 select coalesce(sum(stake),0) into spent from public.casino_rounds where user_id=uid and economy_round=round_id and created_at>=day_start;
 return jsonb_build_object('available',(select greatest(0,balance-reserved_balance-loan_collateral) from public.wallets where user_id=uid),'remaining',greatest(0,100-spent),'active',(select to_jsonb(r) from public.casino_rounds r where user_id=uid and status='active' and game='blackjack'),'recent',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from(select * from public.casino_rounds where user_id=uid and status<>'active' order by created_at desc limit 12) r),'[]'::jsonb));
end $$;
create function private.casino_start(p_game text,p_stake numeric,p_choice text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();spec jsonb;prior private.casino_requests;r public.casino_rounds;round_id bigint;spent numeric;max_return numeric;deck integer[];player integer[];dealer integer[];i integer;j integer;swap integer;number integer;won boolean;red boolean;slot integer:=0;path jsonb:='[]';multiplier numeric;view jsonb;ps integer;ds integer;
begin
 perform pg_advisory_xact_lock(84271001);spec:=jsonb_build_object('kind','start','game',p_game,'stake',p_stake,'choice',p_choice);
 select * into prior from private.casino_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return(select to_jsonb(cr) from public.casino_rounds cr where id=(prior.result->>'id')::uuid);end if;
 if p_request is null or p_game is null or p_game not in('blackjack','roulette','plinko') or p_stake is null or p_stake::text in('NaN','Infinity','-Infinity') or p_stake not between 1 and 5 or p_stake<>trunc(p_stake) then raise exception 'Choose a stake of 1–5 credits';end if;
 if p_game='roulette' and (p_choice is null or p_choice not in('red','black','odd','even')) then raise exception 'Choose red, black, odd or even';end if;
 if p_game<>'roulette' and p_choice is not null then raise exception 'This game does not use a roulette choice';end if;
 if p_game='blackjack' and exists(select 1 from public.casino_rounds where user_id=uid and game='blackjack' and status='active') then raise exception 'Finish your current blackjack hand first';end if;
 select reset_version into round_id from private.economy where id=1;
 select coalesce(sum(stake),0) into spent from public.casino_rounds where user_id=uid and economy_round=round_id and created_at>=date_trunc('day',now() at time zone 'Europe/Zurich') at time zone 'Europe/Zurich';
 if spent+p_stake>100 then raise exception 'Daily games budget reached';end if;
 if not exists(select 1 from public.wallets where user_id=uid and balance-reserved_balance-loan_collateral>=p_stake) then raise exception 'Insufficient available owned credits';end if;
 max_return:=p_stake*case p_game when 'blackjack' then 2.5 when 'roulette' then 2 else 8 end;
 insert into public.casino_rounds(user_id,game,stake,max_payout,economy_round) values(uid,p_game,p_stake,max_return,round_id) returning * into r;
 update public.wallets set balance=balance-p_stake where user_id=uid;insert into public.ledger(user_id,amount,reason) values(uid,-p_stake,'Games: '||p_game||' stake');
 insert into private.credit_accounts(id,balance) values('casino:'||r.id,0);perform private.transfer('treasury','casino:'||r.id,max_return,'Games payout reserve',null);
 if p_game='roulette' then
  number:=private.casino_random(37);red:=number=any(array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]);
  won:=number<>0 and case p_choice when 'red' then red when 'black' then not red when 'odd' then number%2=1 else number%2=0 end;
  perform private.casino_finish(r.id,case when won then 'win' else 'loss' end,case when won then p_stake*2 else 0 end,jsonb_build_object('number',number,'choice',p_choice));
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
create function private.casino_blackjack(p_round uuid,p_action text,p_version integer,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();spec jsonb;prior private.casino_requests;r public.casino_rounds;h private.casino_hands;ps integer;ds integer;outcome text;payout numeric;
begin
 perform pg_advisory_xact_lock(84271001);spec:=jsonb_build_object('kind','blackjack','round',p_round,'action',p_action,'version',p_version);
 select * into prior from private.casino_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return(select to_jsonb(cr) from public.casino_rounds cr where id=(prior.result->>'id')::uuid);end if;
 if p_request is null or p_action is null or p_action not in('hit','stand') then raise exception 'Choose Hit or Stand';end if;
 select * into r from public.casino_rounds where id=p_round and user_id=uid for update;
 if not found or r.game<>'blackjack' or r.status<>'active' then raise exception 'This hand is no longer active';end if;
 if r.version is distinct from p_version then raise exception 'Hand changed; reload the current hand';end if;
 select * into h from private.casino_hands where round_id=r.id for update;
 if p_action='hit' then h.player:=array_append(h.player,h.deck[h.next_card]);h.next_card:=h.next_card+1;end if;
 ps:=private.blackjack_score(h.player);
 if p_action='hit' and ps<21 then
  update private.casino_hands set player=h.player,next_card=h.next_card where round_id=r.id;
  update public.casino_rounds set state=private.blackjack_view(r.id,false),version=version+1 where id=r.id;
 else
  if ps<=21 then while private.blackjack_score(h.dealer)<17 loop h.dealer:=array_append(h.dealer,h.deck[h.next_card]);h.next_card:=h.next_card+1;end loop;end if;
  update private.casino_hands set player=h.player,dealer=h.dealer,next_card=h.next_card where round_id=r.id;ds:=private.blackjack_score(h.dealer);
  outcome:=case when ps>21 then 'loss' when ds>21 or ps>ds then 'win' when ps=ds then 'push' else 'loss' end;
  payout:=case outcome when 'win' then r.stake*2 when 'push' then r.stake else 0 end;
  perform private.casino_finish(r.id,outcome,payout,private.blackjack_view(r.id,true));
 end if;
 select * into r from public.casino_rounds where id=r.id;insert into private.casino_requests values(p_request,uid,spec,to_jsonb(r));return to_jsonb(r);
end $$;
-- The reset refunds unfinished hands before collecting wallets. No reset is executed here.
do $$declare d text;changed text;
begin d:=pg_get_functiondef('private.admin_reset_economy(text,text,uuid)'::regprocedure);
 changed:=replace(d,'for row in select user_id,balance from public.wallets',E'for row in select id,state,stake from public.casino_rounds where status=''active'' order by id loop\n  perform private.casino_finish(row.id,''void'',row.stake,row.state);\n end loop;\n for row in select user_id,balance from public.wallets');
 if changed=d then raise exception 'Reset integration point not found';end if;execute changed;end $$;
create function private.check_casino_reserve() returns trigger language plpgsql security definer set search_path='' as $$
declare rid uuid;r public.casino_rounds;reserve numeric;
begin
 if tg_table_schema='public' then rid:=new.id;else if new.id not like 'casino:%' then return null;end if;rid:=substring(new.id from 8)::uuid;end if;
 select * into r from public.casino_rounds where id=rid;select balance into reserve from private.credit_accounts where id='casino:'||rid;
 if not found or reserve is distinct from (case when r.status='active' then r.max_payout else 0 end) then raise exception 'Game reserve does not reconcile';end if;return null;
end $$;
create constraint trigger casino_reserves after insert or update on public.casino_rounds deferrable initially deferred for each row execute function private.check_casino_reserve();
create constraint trigger casino_account_reserves after insert or update on private.credit_accounts deferrable initially deferred for each row execute function private.check_casino_reserve();
create function public.casino_state() returns jsonb language sql security invoker set search_path='' as $$select private.casino_state()$$;
create function public.casino_start(p_game text,p_stake numeric,p_choice text,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.casino_start(p_game,p_stake,p_choice,p_request)$$;
create function public.casino_blackjack(p_round uuid,p_action text,p_version integer,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.casino_blackjack(p_round,p_action,p_version,p_request)$$;
revoke all on function private.casino_random(integer),private.blackjack_score(integer[]),private.blackjack_view(uuid,boolean),private.casino_finish(uuid,text,numeric,jsonb),private.check_casino_reserve() from public,anon,authenticated;
revoke all on function private.casino_state(),public.casino_state(),private.casino_start(text,numeric,text,uuid),public.casino_start(text,numeric,text,uuid),private.casino_blackjack(uuid,text,integer,uuid),public.casino_blackjack(uuid,text,integer,uuid) from public,anon,authenticated;
grant execute on function private.casino_state(),public.casino_state(),private.casino_start(text,numeric,text,uuid),public.casino_start(text,numeric,text,uuid),private.casino_blackjack(uuid,text,integer,uuid),public.casino_blackjack(uuid,text,integer,uuid) to authenticated;
