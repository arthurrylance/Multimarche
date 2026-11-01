create or replace function private.casino_plinko_batch(p_stake numeric,p_count integer,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 return (select jsonb_agg(to_jsonb(cr) order by array_position(rounds,cr.id)) from public.casino_rounds cr where cr.id=any(rounds));
end $$;

