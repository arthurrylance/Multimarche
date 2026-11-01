-- Member game limits and treasury-funded, server-replayed Snake rewards.
create table private.game_settings(id integer primary key check(id=1),casino_daily_limit integer not null default 100 check(casino_daily_limit between 0 and 10000));
insert into private.game_settings values(1,100);
alter table private.game_settings enable row level security;
revoke all on private.game_settings from public,anon,authenticated;
create function private.game_settings() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_member();return (select jsonb_build_object('casino_daily_limit',casino_daily_limit,'snake_daily_limit',100) from private.game_settings where id=1);end $$;
create function private.admin_game_settings(p_daily_limit integer,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();prior public.admin_events;before_limit integer;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null or p_daily_limit is null or p_daily_limit not between 0 and 10000 then raise exception 'Choose a daily casino limit from 0 to 10000';end if;
 select * into prior from public.admin_events where id=p_request;
 if found then if prior.actor_id<>uid or prior.action<>'casino_limit' or (prior.details->>'limit')::integer<>p_daily_limit then raise exception 'Request ID already used';end if;return private.game_settings();end if;
 select casino_daily_limit into before_limit from private.game_settings where id=1;
 update private.game_settings set casino_daily_limit=p_daily_limit where id=1;
 insert into public.admin_events(id,actor_id,action,reason,details) values(p_request,uid,'casino_limit','Daily casino wagering limit',jsonb_build_object('before',before_limit,'limit',p_daily_limit));
 return private.game_settings();
end $$;
create or replace function private.casino_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();round_id bigint;spent numeric;day_start timestamptz;
begin
 select reset_version into round_id from private.economy where id=1;day_start:=date_trunc('day',now() at time zone 'Europe/Zurich') at time zone 'Europe/Zurich';
 select coalesce(sum(stake),0) into spent from public.casino_rounds where user_id=uid and economy_round=round_id and created_at>=day_start;
 return jsonb_build_object('available',(select greatest(0,balance-reserved_balance-loan_collateral) from public.wallets where user_id=uid),'remaining',greatest(0,(select casino_daily_limit from private.game_settings where id=1)-spent),'daily_limit',(select casino_daily_limit from private.game_settings where id=1),'active',(select to_jsonb(r) from public.casino_rounds r where user_id=uid and status='active' and game='blackjack'),'recent',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from(select * from public.casino_rounds where user_id=uid and status<>'active' order by created_at desc limit 12) r),'[]'::jsonb));
end $$;
create or replace function private.casino_start(p_game text,p_stake numeric,p_choice text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if spent+p_stake>(select casino_daily_limit from private.game_settings where id=1) then raise exception 'Daily games budget reached';end if;
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

create table private.plinko_batches(request_id uuid primary key,user_id uuid not null references public.profiles(id),stake numeric not null,ball_count integer not null,round_ids uuid[] not null);
create index plinko_batches_user_idx on private.plinko_batches(user_id);
alter table private.plinko_batches enable row level security;revoke all on private.plinko_batches from public,anon,authenticated;
create function private.casino_plinko_batch(p_stake numeric,p_count integer,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();prior private.plinko_batches;rounds uuid[]:='{}';r jsonb;i integer;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null or p_count is null or p_count not between 1 and 10 then raise exception 'Choose 1–10 balls';end if;
 select * into prior from private.plinko_batches where request_id=p_request;
 if found then if prior.user_id<>uid or prior.stake is distinct from p_stake or prior.ball_count<>p_count then raise exception 'Request ID already used';end if;rounds:=prior.round_ids;
 else
  for i in 1..p_count loop
   r:=private.casino_start('plinko',p_stake,null,(md5(p_request::text||':plinko:'||i))::uuid);rounds:=array_append(rounds,(r->>'id')::uuid);
  end loop;
  insert into private.plinko_batches values(p_request,uid,p_stake,p_count,rounds);
 end if;
 return (select jsonb_agg(to_jsonb(r) order by array_position(rounds,r.id)) from public.casino_rounds r where id=any(rounds));
end $$;

-- Snake simulation is deterministic on client and server; clients submit directions, never scores.
create function private.snake_apple(p_body integer[],p_seed bigint) returns jsonb language plpgsql immutable set search_path='' as $$
declare seed bigint:=(p_seed*48271)%2147483647;cell integer;i integer;
begin
 if cardinality(p_body)>=400 then return jsonb_build_object('seed',seed,'apple',-1);end if;
 for i in 0..399 loop cell:=((seed%400)::integer+i)%400;if not cell=any(p_body) then return jsonb_build_object('seed',seed,'apple',cell);end if;end loop;
 raise exception 'No apple cell';
end $$;
create function private.snake_move(p_state jsonb,p_direction integer) returns jsonb language plpgsql immutable set search_path='' as $$
declare body integer[];direction integer:=(p_state->>'direction')::integer;head integer;next_cell integer;apple integer:=(p_state->>'apple')::integer;grow boolean;next_apple jsonb;steps integer:=(p_state->>'steps')::integer+1;score integer:=(p_state->>'score')::integer;
begin
 if p_direction is null or p_direction not between 0 and 3 or (p_state->>'over')::boolean then raise exception 'Invalid Snake move';end if;
 select array_agg(value::integer order by ord) into body from jsonb_array_elements_text(p_state->'body') with ordinality t(value,ord);
 if (p_direction+2)%4<>direction then direction:=p_direction;end if;
 head:=body[1];next_cell:=head+(array[-20,1,20,-1])[direction+1];
 if next_cell<0 or next_cell>=400 or (direction=1 and head%20=19) or (direction=3 and head%20=0) then return p_state||jsonb_build_object('direction',direction,'steps',steps,'over',true);end if;
 grow:=next_cell=apple;
 if next_cell=any(case when grow then body else body[1:cardinality(body)-1] end) then return p_state||jsonb_build_object('direction',direction,'steps',steps,'over',true);end if;
 body:=array_prepend(next_cell,case when grow then body else body[1:cardinality(body)-1] end);
 if grow then score:=score+1;next_apple:=private.snake_apple(body,(p_state->>'seed')::bigint);else next_apple:=p_state;end if;
 return jsonb_build_object('body',body,'direction',direction,'apple',(next_apple->>'apple')::integer,'seed',(next_apple->>'seed')::bigint,'steps',steps,'score',score,'over',cardinality(body)>=400);
end $$;
create table private.snake_sessions(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),state jsonb not null,awarded integer not null default 0,economy_round bigint not null,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),status text not null default 'active' check(status in('active','over')));
create unique index snake_one_active_user on private.snake_sessions(user_id) where status='active';
create index snake_user_history on private.snake_sessions(user_id,created_at desc);
create table private.snake_daily(user_id uuid not null references public.profiles(id),day date not null,economy_round bigint not null,earned integer not null default 0 check(earned between 0 and 100),primary key(user_id,day,economy_round));
create table private.snake_requests(request_id uuid primary key,user_id uuid not null references public.profiles(id),spec jsonb not null,result jsonb not null);
create index snake_requests_user_idx on private.snake_requests(user_id);
alter table private.snake_sessions enable row level security;alter table private.snake_daily enable row level security;alter table private.snake_requests enable row level security;
revoke all on private.snake_sessions,private.snake_daily,private.snake_requests from public,anon,authenticated;
create function private.snake_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();round_id bigint;earned integer;session jsonb;
begin
 select reset_version into round_id from private.economy where id=1;
 select d.earned into earned from private.snake_daily d where user_id=uid and day=(now() at time zone 'Europe/Zurich')::date and economy_round=round_id;
 select to_jsonb(s) into session from private.snake_sessions s where user_id=uid and status='active' and economy_round=round_id and created_at>now()-interval '30 minutes';
 return jsonb_build_object('session',session,'earned',coalesce(earned,0),'remaining',100-coalesce(earned,0),'daily_limit',100,'tick_ms',140);
end $$;
create function private.snake_start(p_restart boolean,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();spec jsonb:=jsonb_build_object('kind','start','restart',p_restart);prior private.snake_requests;r private.snake_sessions;round_id bigint;apple jsonb;result jsonb;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null or p_restart is null then raise exception 'Invalid request';end if;
 select * into prior from private.snake_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 select reset_version into round_id from private.economy where id=1;
 select * into r from private.snake_sessions where user_id=uid and status='active' for update;
 if found and (p_restart or r.economy_round<>round_id or r.created_at<clock_timestamp()-interval '30 minutes') then update private.snake_sessions set status='over',updated_at=clock_timestamp() where id=r.id;r.id:=null;end if;
 if r.id is null then
  apple:=private.snake_apple(array[210,209,208],private.casino_random(1000000)+1);
  insert into private.snake_sessions(user_id,economy_round,state) values(uid,round_id,jsonb_build_object('body',array[210,209,208],'direction',1,'apple',(apple->>'apple')::integer,'seed',(apple->>'seed')::bigint,'score',0,'steps',0,'over',false)) returning * into r;
 end if;
 result:=private.snake_state()||jsonb_build_object('session',to_jsonb(r));insert into private.snake_requests values(p_request,uid,spec,result);return result;
end $$;
create function private.snake_step(p_session uuid,p_step integer,p_moves integer[],p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();prior private.snake_requests;spec jsonb:=jsonb_build_object('kind','step','session',p_session,'step',p_step,'moves',p_moves);r private.snake_sessions;next_state jsonb;direction integer;earned integer;reward integer;gained integer;round_id bigint;day_id date:=(clock_timestamp() at time zone 'Europe/Zurich')::date;result jsonb;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null or p_session is null or p_step is null or p_moves is null or cardinality(p_moves) not between 1 and 40 or array_ndims(p_moves)<>1 then raise exception 'Invalid move batch';end if;
 select * into prior from private.snake_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 select * into r from private.snake_sessions where id=p_session and user_id=uid for update;
 if not found then raise exception 'Snake game not found';end if;
 select reset_version into round_id from private.economy where id=1;
 if r.status<>'active' or r.economy_round<>round_id or r.created_at<clock_timestamp()-interval '30 minutes' then raise exception 'Start a new Snake game';end if;
 if p_step<>(r.state->>'steps')::integer then raise exception 'This game changed in another tab. Reload the game.';end if;
 if p_step+cardinality(p_moves)>floor(extract(epoch from clock_timestamp()-r.created_at)*1000/140) then raise exception 'Moves arrived too quickly. Retry.';end if;
 next_state:=r.state;
 foreach direction in array p_moves loop next_state:=private.snake_move(next_state,direction);end loop;
 gained:=(next_state->>'score')::integer-(r.state->>'score')::integer;
 insert into private.snake_daily(user_id,day,economy_round) values(uid,day_id,round_id) on conflict do nothing;
 select d.earned into earned from private.snake_daily d where user_id=uid and day=day_id and economy_round=round_id for update;
 reward:=least(gained,100-earned);
 if reward>0 then
  -- Existing wallet ledger triggers transfer from treasury and append to the audit chain.
  update public.wallets set balance=balance+reward where user_id=uid;
  insert into public.ledger(user_id,amount,reason) values(uid,reward,'Snake: '||reward||' apples');
  update private.snake_daily set earned=earned+reward where user_id=uid and day=day_id and economy_round=round_id;
 end if;
 update private.snake_sessions set state=next_state,awarded=awarded+reward,status=case when (next_state->>'over')::boolean then 'over' else 'active' end,updated_at=clock_timestamp() where id=r.id returning * into r;
 result:=private.snake_state()||jsonb_build_object('session',to_jsonb(r));insert into private.snake_requests values(p_request,uid,spec,result);return result;
end $$;
create function public.game_settings() returns jsonb language sql security invoker set search_path='' as $$select private.game_settings()$$;
create function public.admin_game_settings(p_daily_limit integer,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.admin_game_settings(p_daily_limit,p_request)$$;
create function public.casino_plinko_batch(p_stake numeric,p_count integer,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.casino_plinko_batch(p_stake,p_count,p_request)$$;
create function public.snake_state() returns jsonb language sql security invoker set search_path='' as $$select private.snake_state()$$;
create function public.snake_start(p_restart boolean,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.snake_start(p_restart,p_request)$$;
create function public.snake_step(p_session uuid,p_step integer,p_moves integer[],p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.snake_step(p_session,p_step,p_moves,p_request)$$;
revoke all on function private.snake_apple(integer[],bigint),private.snake_move(jsonb,integer) from public,anon,authenticated;
revoke all on function public.game_settings(),private.game_settings(),public.admin_game_settings(integer,uuid),private.admin_game_settings(integer,uuid),public.casino_plinko_batch(numeric,integer,uuid),private.casino_plinko_batch(numeric,integer,uuid),public.snake_state(),private.snake_state(),public.snake_start(boolean,uuid),private.snake_start(boolean,uuid),public.snake_step(uuid,integer,integer[],uuid),private.snake_step(uuid,integer,integer[],uuid) from public,anon,authenticated;
grant execute on function public.game_settings(),private.game_settings(),public.admin_game_settings(integer,uuid),private.admin_game_settings(integer,uuid),public.casino_plinko_batch(numeric,integer,uuid),private.casino_plinko_batch(numeric,integer,uuid),public.snake_state(),private.snake_state(),public.snake_start(boolean,uuid),private.snake_start(boolean,uuid),public.snake_step(uuid,integer,integer[],uuid),private.snake_step(uuid,integer,integer[],uuid) to authenticated;
