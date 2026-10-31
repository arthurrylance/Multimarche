-- The site-wide signal can advance once every two minutes, regardless of caller.
create or replace function private.trigger_emergency() returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();s public.emergency_signal;
begin
 perform pg_advisory_xact_lock(84271001);
 select * into s from public.emergency_signal where id=1 for update;
 if s.triggered_at>clock_timestamp()-interval '2 minutes' then return s.version;end if;
 update public.emergency_signal set version=version+1,triggered_at=clock_timestamp() where id=1 returning * into s;
 insert into public.admin_events(actor_id,action,reason,details) values(uid,'emergency_redirect','Shared school-page redirect',jsonb_build_object('version',s.version));
 return s.version;
end $$;

-- A round boundary separates new play from archived testing results without deleting records.
alter table private.economy add column reset_version bigint not null default 0;
alter table private.economy add column last_reset_at timestamptz;
alter table public.markets add column economy_round bigint not null default 0;
create function private.assign_market_round() returns trigger language plpgsql security definer set search_path='' as $$
begin select reset_version into new.economy_round from private.economy where id=1;return new;end $$;
create trigger assign_market_round before insert on public.markets for each row execute function private.assign_market_round();
revoke all on function private.assign_market_round() from public,anon,authenticated;
-- Existing creation quotas apply to the current round. Retries retain their original group IDs.
do $$declare signature text;definition text;changed text;
begin
 foreach signature in array array['private.create_market_v3(text,text,text,timestamptz,numeric,integer)','private.create_market_v5(text,text,text,timestamptz,integer,boolean,text)','private.create_market_group(text,jsonb,timestamptz,integer,boolean,text,text,uuid)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  changed:=replace(definition,'where creator_id=uid and created_at>','where creator_id=uid and economy_round=(select reset_version from private.economy where id=1) and created_at>');
  if changed=definition then raise exception 'Missing creation quota guard: %',signature;end if;
  execute changed;
 end loop;
end $$;
create or replace function private.loss_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();h record;t record;m public.markets;quantity numeric;basis numeric;released numeric;cash numeric;open_basis numeric:=0;net numeric:=0;payout numeric;baseline numeric;loss numeric;latest timestamptz;cutoff timestamptz:=now()-interval '24 hours';round_id bigint;
begin
 select reset_version into round_id from private.economy where id=1;
 select balance into cash from public.wallets where user_id=uid;
 for h in select distinct t.market_id,t.side from public.trades t join public.markets current_market on current_market.id=t.market_id where t.user_id=uid and current_market.economy_round=round_id loop
  quantity:=0;basis:=0;
  for t in select * from public.trades where user_id=uid and market_id=h.market_id and side=h.side order by created_at,sequence loop
   if t.action='buy' then quantity:=quantity+t.shares;basis:=basis+t.total;
   else
    released:=case when quantity>0 then basis*least(t.shares,quantity)/quantity else 0 end;
    quantity:=greatest(0,quantity-t.shares);basis:=greatest(0,basis-released);
    if t.created_at>=cutoff then net:=net+t.total-released;latest:=greatest(latest,t.created_at);end if;
   end if;
  end loop;
  select * into m from public.markets where id=h.market_id;
  if m.status='resolved' then
   payout:=quantity*case when m.outcome='void' then .5 when m.outcome=h.side then 1 else 0 end;
   if m.resolved_at>=cutoff then net:=net+payout-basis;latest:=greatest(latest,m.resolved_at);end if;
  else open_basis:=open_basis+basis;end if;
 end loop;
 baseline:=greatest(0,round(cash+open_basis-net,2));loss:=greatest(0,round(-net,2));
 return jsonb_build_object('window_hours',24,'loss',loss,'baseline',baseline,'ratio',case when baseline>0 then loss/baseline else 0 end,'triggered',baseline>0 and loss>=baseline*.5,'key',round_id::text||':'||coalesce(latest::text,'none')||':'||loss::text);
end $$;

create function private.admin_reset_economy(p_confirmation text,p_reason text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();prior public.admin_events;row record;reason text:=coalesce(nullif(btrim(p_reason),''),'Fresh start');users integer;closed integer:=0;cancelled integer:=0;archived integer;new_round bigint;reset_time timestamptz;result jsonb;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_confirmation is distinct from 'RESET ALL' then raise exception 'Type RESET ALL to confirm';end if;
 if p_request is null then raise exception 'A request ID is required';end if;
 select * into prior from public.admin_events where id=p_request;
 if found then
  if prior.actor_id<>uid or prior.action<>'economy_reset' or prior.reason<>reason then raise exception 'Request ID already used for another action';end if;
  return prior.details;
 end if;
 select count(*) into users from public.profiles p join public.wallets w on w.user_id=p.id where p.active;
 if users*1000::numeric>(select total_supply from private.economy where id=1) then raise exception 'The issued supply cannot fund 1,000 credits per active account';end if;
 for row in select id from public.orders where status='open' order by sequence loop
  if private.close_order(row.id,'cancelled','Economy reset') then cancelled:=cancelled+1;end if;
 end loop;
 for row in select id from public.markets where status<>'resolved' order by id loop
  perform private.admin_market(row.id,'settle','{"outcome":"void"}', 'Economy reset: '||reason);closed:=closed+1;
 end loop;
 update public.markets set archived=true where not archived;
 get diagnostics archived=row_count;
 -- Reclaim cash first, then distribute the same existing supply. No issuance or audit rewriting.
 for row in select user_id,balance from public.wallets order by user_id loop
  if row.balance<>0 then
   update public.wallets set balance=0 where user_id=row.user_id;
   insert into public.ledger(user_id,amount,reason) values(row.user_id,-row.balance,'Economy reset: reclaim');
  end if;
 end loop;
 for row in select w.user_id from public.wallets w join public.profiles p on p.id=w.user_id where p.active order by w.user_id loop
  update public.wallets set balance=1000 where user_id=row.user_id;
  insert into public.ledger(user_id,amount,reason) values(row.user_id,1000,'Economy reset: starting credits');
 end loop;
 update private.economy set reset_version=reset_version+1,last_reset_at=clock_timestamp() where id=1 returning reset_version,last_reset_at into new_round,reset_time;
 result:=jsonb_build_object('round',new_round,'reset_at',reset_time,'users',users,'starting_balance',1000,'closed_markets',closed,'cancelled_orders',cancelled,'archived_markets',archived,'treasury',(select balance from private.credit_accounts where id='treasury'),'total_supply',(select total_supply from private.economy where id=1));
 insert into public.admin_events(id,actor_id,action,reason,details) values(p_request,uid,'economy_reset',reason,result);
 return result;
end $$;
create function public.admin_reset_economy(p_confirmation text,p_reason text,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.admin_reset_economy(p_confirmation,p_reason,p_request)$$;
revoke all on function private.admin_reset_economy(text,text,uuid),public.admin_reset_economy(text,text,uuid) from public,anon,authenticated;
grant execute on function private.admin_reset_economy(text,text,uuid),public.admin_reset_economy(text,text,uuid) to authenticated;
create or replace function private.economy_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_member();return jsonb_build_object('total_supply',(select total_supply from private.economy where id=1),'treasury',(select balance from private.credit_accounts where id='treasury'),'wallets',(select coalesce(sum(balance),0) from public.wallets),'reserved',(select coalesce(sum(balance),0) from private.credit_accounts where id like 'market:%'),'height',(select coalesce(max(seq),0) from public.audit_blocks),'reset_version',(select reset_version from private.economy where id=1),'last_reset_at',(select last_reset_at from private.economy where id=1));end $$;
