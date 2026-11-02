-- Summaries affect presentation only; the underlying credit ledger stays intact.
create function public.portfolio_history(p_limit integer default 100)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare uid uuid:=private.require_member();
begin
 return (
  with own_entries as (
   select l.id,l.reason,l.amount,l.created_at,
    (l.created_at at time zone 'Europe/Zurich')::date as day,
    case when l.reason like 'Snake:%' then 'snake'
     when l.reason ~ '^Games: (blackjack|roulette|plinko) ' then split_part(l.reason,' ',2)
     else null end as game
   from public.ledger l where l.user_id=uid
  ), display_entries as (
   select id::text,reason,amount,created_at,null::text as game,null::date as day,
    0::numeric as spent,0::numeric as received,1::bigint as transactions
   from own_entries where game is null
   union all
   select 'game:'||game||':'||day::text,initcap(game)||' · daily summary',sum(amount),max(created_at),game,day,
    -coalesce(sum(amount) filter(where amount<0),0),
    coalesce(sum(amount) filter(where amount>0),0),count(*)
   from own_entries where game is not null group by game,day
  )
  select coalesce(jsonb_agg(to_jsonb(entry) order by entry.created_at desc,entry.id),'[]'::jsonb)
  from (select * from display_entries order by created_at desc,id limit greatest(1,least(100,coalesce(p_limit,100)))) entry
 );
end $$;
revoke all on function public.portfolio_history(integer) from public,anon,authenticated;
grant execute on function public.portfolio_history(integer) to authenticated;
