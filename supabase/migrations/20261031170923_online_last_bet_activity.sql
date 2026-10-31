create index trades_last_buy_idx on public.trades(user_id,created_at desc) where action='buy';
create function private.online_member_activity() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.require_member();
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',users.user_id,'last_bet_at',activity.last_bet_at) order by users.user_id)
 from (select distinct presence.user_id from public.member_presence presence join public.profiles p on p.id=presence.user_id where p.active and presence.last_seen>now()-interval '60 seconds') users
 left join lateral (select max(t.created_at) last_bet_at from public.trades t where t.user_id=users.user_id and t.action='buy') activity on true),'[]'::jsonb);
end $$;
create function public.online_member_activity() returns jsonb language sql security invoker set search_path='' as $$select private.online_member_activity()$$;
revoke all on function private.online_member_activity(),public.online_member_activity() from public,anon,authenticated;
grant execute on function private.online_member_activity(),public.online_member_activity() to authenticated;
