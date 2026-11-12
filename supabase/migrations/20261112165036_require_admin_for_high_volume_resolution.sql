-- Member votes can propose an outcome for high-volume markets. Only an admin can settle them.
create or replace function private.reconcile_resolution(p_market uuid) returns text language plpgsql security definer set search_path='' as $$
declare m public.markets;kinds integer;confirmations integer;winner text;pay record;
begin
 perform private.require_member();perform pg_advisory_xact_lock(84271001);
 select * into m from public.markets where id=p_market for update;
 if not found or m.status='resolved' then raise exception 'No unresolved market';end if;
 select count(distinct outcome),count(*),min(outcome) into kinds,confirmations,winner from public.resolution_votes where market_id=p_market;
 if kinds=0 then
  update public.markets set status='open',outcome=null,resolution_disputed=false,state_changed_at=clock_timestamp() where id=p_market;return 'open';
 elsif kinds>1 then
  update public.markets set status='proposed',outcome=null,resolution_disputed=true,state_changed_at=clock_timestamp() where id=p_market;return 'disputed';
 elsif confirmations<m.required_verifications or m.volume>2000 then
  update public.markets set status='proposed',outcome=winner,resolution_disputed=false,state_changed_at=clock_timestamp() where id=p_market;return 'proposed';
 end if;
 for pay in select user_id,sum(shares*case when winner='void' then .5 when side=winner then 1 else 0 end) amount from public.positions where market_id=p_market group by user_id order by user_id loop
  update public.wallets set balance=balance+pay.amount where user_id=pay.user_id;
  insert into public.ledger(user_id,market_id,amount,reason) values(pay.user_id,p_market,pay.amount,'Settlement: '||winner);
 end loop;
 update public.markets set status='resolved',outcome=winner,resolved_at=now(),resolution_disputed=false,probability=case winner when 'yes' then 1 when 'no' then 0 else .5 end where id=p_market;return 'resolved';
end $$;
