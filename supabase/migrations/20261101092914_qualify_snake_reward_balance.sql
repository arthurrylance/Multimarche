create or replace function private.snake_step(p_session uuid,p_step integer,p_moves integer[],p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
  update private.snake_daily d set earned=d.earned+reward where d.user_id=uid and d.day=day_id and d.economy_round=round_id;
 end if;
 update private.snake_sessions set state=next_state,awarded=awarded+reward,status=case when (next_state->>'over')::boolean then 'over' else 'active' end,updated_at=clock_timestamp() where id=r.id returning * into r;
 result:=private.snake_state()||jsonb_build_object('session',to_jsonb(r));insert into private.snake_requests values(p_request,uid,spec,result);return result;
end $$;
