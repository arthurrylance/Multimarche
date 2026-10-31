alter table public.profiles add column frozen_until timestamptz;
alter table public.markets add column history_deleted_at timestamptz;
alter table public.trades add column sequence bigint generated always as identity;
create unique index trades_sequence_idx on public.trades(sequence);
create index trades_member_history_idx on public.trades(user_id,market_id,side,created_at,sequence);

create function private.can_participate() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=auth.uid() and active and (frozen_until is null or frozen_until<=now()))$$;
create function private.require_player() returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();until_time timestamptz;
begin
 select frozen_until into until_time from public.profiles where id=uid;
 if until_time>clock_timestamp() then raise exception 'Account timed out until %',until_time;end if;
 return uid;
end $$;
-- Preserve each transaction's pricing/settlement implementation and its function OID.
do $$declare signature text;definition text;
begin
 foreach signature in array array['private.trade(uuid,text,text,numeric,numeric,uuid)','private.create_market(text,text,text,text,timestamptz)','private.create_market_v2(text,text,text,timestamptz,numeric)','private.create_market_v3(text,text,text,timestamptz,numeric,integer)','private.resolve_market(uuid,text,text)','private.withdraw_resolution(uuid)','private.change_counter(uuid,integer,uuid)','private.set_counter_enabled(uuid,boolean,text)'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if position('private.require_member()' in definition)=0 then raise exception 'Missing access check in %',signature;end if;
  execute replace(definition,'private.require_member()','private.require_player()');
 end loop;
end $$;
revoke execute on function private.trade_v1(uuid,text,text,numeric,numeric,uuid) from public,anon,authenticated;
revoke all on function private.can_participate(),private.require_player() from public,anon,authenticated;
grant execute on function private.can_participate() to authenticated;
alter policy add_comment on public.comments with check(user_id=(select auth.uid()) and (select private.can_participate()) and exists(select 1 from public.markets m where m.id=market_id));

create function private.admin_nickname(p_user uuid,p_nickname text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();
begin
 perform pg_advisory_xact_lock(84271001);
 if p_nickname is null or length(trim(p_nickname))>40 then raise exception 'Nickname must be at most 40 characters';end if;
 update public.profiles set nickname=trim(p_nickname) where id=p_user and active;
 if not found then raise exception 'Choose an active member';end if;
 insert into public.admin_events(actor_id,action,target_id,reason) values(uid,'nickname_changed',p_user::text,'Admin changed display nickname');
end $$;
create function private.admin_timeout(p_user uuid,p_minutes integer) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();until_time timestamptz;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_user=uid then raise exception 'You cannot time out yourself';end if;
 if p_minutes is null or p_minutes<0 or p_minutes>10080 then raise exception 'Choose up to seven days, or zero to unfreeze';end if;
 if p_minutes>0 and exists(select 1 from private.admins where user_id=p_user) then raise exception 'Remove admin access before applying a timeout';end if;
 until_time:=case when p_minutes=0 then null else clock_timestamp()+make_interval(mins=>p_minutes) end;
 update public.profiles set frozen_until=until_time where id=p_user and active;
 if not found then raise exception 'Choose an active member';end if;
 insert into public.admin_events(actor_id,action,target_id,reason,details) values(uid,case when p_minutes=0 then 'timeout_removed' else 'member_timeout' end,p_user::text,case when p_minutes=0 then 'Account unfrozen' else 'Temporary account timeout' end,jsonb_build_object('until',until_time));
end $$;
-- A timed-out member cannot receive admin privileges until the timeout is removed.
do $$declare definition text;
begin
 definition:=pg_get_functiondef('private.admin_set_role(uuid,boolean)'::regprocedure);
 definition:=replace(definition,'if p_admin is null','if p_admin and exists(select 1 from public.profiles where id=p_user and frozen_until>now()) then raise exception ''Unfreeze the member before granting admin access'';end if; if p_admin is null');
 execute definition;
end $$;

create function private.admin_history(p_market uuid,p_deleted boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();
begin
 perform pg_advisory_xact_lock(84271001);
 if p_deleted is null then raise exception 'Choose a history action';end if;
 update public.markets set history_deleted_at=case when p_deleted then clock_timestamp() else null end where id=p_market and status='resolved';
 if not found then raise exception 'Only settled markets can be removed from history';end if;
 insert into public.admin_events(actor_id,action,target_id,reason) values(uid,case when p_deleted then 'history_deleted' else 'history_restored' end,p_market::text,'History visibility changed; financial records retained');
end $$;
alter policy members_markets on public.markets using((select private.is_member()) and (history_deleted_at is null or (select private.is_admin())));
alter policy members_trades on public.trades using((select private.is_member()) and exists(select 1 from public.markets m where m.id=market_id));
alter policy members_votes on public.resolution_votes using((select private.is_member()) and exists(select 1 from public.markets m where m.id=market_id));
alter policy members_comments on public.comments using((select private.is_member()) and exists(select 1 from public.markets m where m.id=market_id));
alter policy members_counter_events on public.counter_events using((select private.is_member()) and exists(select 1 from public.markets m where m.id=market_id));
do $$declare definition text;
begin
 definition:=pg_get_functiondef('private.market_history(uuid)'::regprocedure);
 definition:=replace(definition,'if not found or m.status<>''resolved''','if not found or (m.history_deleted_at is not null and not private.is_admin()) or m.status<>''resolved''');
 execute definition;
end $$;

-- Server-owned identities and timestamps; separate tabs keep separate leases.
create table public.member_presence(user_id uuid not null references public.profiles(id),tab_id uuid not null,last_seen timestamptz not null default now(),primary key(user_id,tab_id));
alter table public.member_presence enable row level security;
create index member_presence_seen_idx on public.member_presence(last_seen);
create policy read_member_presence on public.member_presence for select to authenticated using((select private.is_member()));
revoke all on public.member_presence from public,anon,authenticated;
grant select on public.member_presence to authenticated;
create function private.presence_ping(p_tab uuid,p_online boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();
begin
 if p_tab is null or p_online is null then raise exception 'Invalid presence';end if;
 delete from public.member_presence where user_id=uid and last_seen<clock_timestamp()-interval '75 seconds';
 if not p_online then delete from public.member_presence where user_id=uid and tab_id=p_tab;return;end if;
 if (select count(*) from public.member_presence where user_id=uid)>=20 and not exists(select 1 from public.member_presence where user_id=uid and tab_id=p_tab) then raise exception 'Too many tabs';end if;
 insert into public.member_presence values(uid,p_tab,clock_timestamp()) on conflict(user_id,tab_id) do update set last_seen=excluded.last_seen;
end $$;
create function private.online_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_member();return coalesce((select jsonb_agg(user_id) from (select distinct s.user_id from public.member_presence s join public.profiles p on p.id=s.user_id where p.active and s.last_seen>now()-interval '60 seconds') users),'[]'::jsonb);end $$;
alter publication supabase_realtime add table public.member_presence;

create or replace function private.admin_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_admin();return coalesce((select jsonb_agg(jsonb_build_object(
 'id',p.id,'username',p.username,'nickname',p.nickname,'active',p.active,'deleted_at',p.deleted_at,'auth_deleted_at',p.auth_deleted_at,'frozen_until',p.frozen_until,'created_at',p.created_at,'balance',w.balance,
 'admin',exists(select 1 from private.admins a where a.user_id=p.id),
 'equity',w.balance+coalesce((select sum(pos.shares*case when pos.side='yes' then m.probability else 1-m.probability end) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and m.status<>'resolved'),0),
 'open_bets',(select count(distinct pos.market_id) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and pos.shares>0 and m.status<>'resolved'),
 'spent',(select coalesce(sum(total),0) from public.trades where user_id=p.id and action='buy'),
 'sales',(select coalesce(sum(total),0) from public.trades where user_id=p.id and action='sell'),
 'payouts',(select coalesce(sum(amount),0) from public.ledger where user_id=p.id and reason like 'Settlement:%')
 ) order by p.username) from public.profiles p join public.wallets w on w.user_id=p.id),'[]'::jsonb);end $$;

-- Realised P/L uses average acquisition cost, never treating an open buy as a loss.
create function private.loss_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();h record;t record;m public.markets;quantity numeric;basis numeric;released numeric;cash numeric;open_basis numeric:=0;net numeric:=0;payout numeric;baseline numeric;loss numeric;latest timestamptz;cutoff timestamptz:=now()-interval '24 hours';
begin
 select balance into cash from public.wallets where user_id=uid;
 for h in select distinct market_id,side from public.trades where user_id=uid loop
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
 return jsonb_build_object('window_hours',24,'loss',loss,'baseline',baseline,'ratio',case when baseline>0 then loss/baseline else 0 end,'triggered',baseline>0 and loss>=baseline*.5,'key',coalesce(latest::text,'none')||':'||loss::text);
end $$;

create function public.admin_nickname(p_user uuid,p_nickname text) returns void language sql security invoker set search_path='' as $$select private.admin_nickname(p_user,p_nickname)$$;
create function public.admin_timeout(p_user uuid,p_minutes integer) returns void language sql security invoker set search_path='' as $$select private.admin_timeout(p_user,p_minutes)$$;
create function public.admin_history(p_market uuid,p_deleted boolean) returns void language sql security invoker set search_path='' as $$select private.admin_history(p_market,p_deleted)$$;
create function public.presence_ping(p_tab uuid,p_online boolean) returns void language sql security invoker set search_path='' as $$select private.presence_ping(p_tab,p_online)$$;
create function public.online_members() returns jsonb language sql security invoker set search_path='' as $$select private.online_members()$$;
create function public.loss_summary() returns jsonb language sql security invoker set search_path='' as $$select private.loss_summary()$$;
revoke all on function private.admin_nickname(uuid,text),private.admin_timeout(uuid,integer),private.admin_history(uuid,boolean),private.presence_ping(uuid,boolean),private.online_members(),private.loss_summary(),public.admin_nickname(uuid,text),public.admin_timeout(uuid,integer),public.admin_history(uuid,boolean),public.presence_ping(uuid,boolean),public.online_members(),public.loss_summary() from public,anon,authenticated;
grant execute on function private.admin_nickname(uuid,text),private.admin_timeout(uuid,integer),private.admin_history(uuid,boolean),private.presence_ping(uuid,boolean),private.online_members(),private.loss_summary(),public.admin_nickname(uuid,text),public.admin_timeout(uuid,integer),public.admin_history(uuid,boolean),public.presence_ping(uuid,boolean),public.online_members(),public.loss_summary() to authenticated;
