create or replace function private.withdraw_resolution(p_market uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();
begin
 perform pg_advisory_xact_lock(84271001);
 if not exists(select 1 from public.markets where id=p_market and status='proposed') then raise exception 'No pending proposal';end if;
 delete from public.resolution_votes where market_id=p_market and user_id=uid;
 if not found then raise exception 'You have no confirmation to withdraw';end if;
 if not exists(select 1 from public.resolution_votes where market_id=p_market) then
  update public.markets set status='open',outcome=null where id=p_market;
 end if;
end $$;
