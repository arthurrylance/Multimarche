-- Non-personal shared redirect signal; visitors can receive but cannot trigger it.
create table public.emergency_signal(id integer primary key check(id=1),version bigint not null default 0,triggered_at timestamptz);
insert into public.emergency_signal(id) values(1);
alter table public.emergency_signal enable row level security;
create policy receive_emergency on public.emergency_signal for select to anon,authenticated using(true);
revoke all on public.emergency_signal from public,anon,authenticated;
grant select on public.emergency_signal to anon,authenticated;

alter table public.markets add column counter_enabled boolean not null default false;
alter table public.markets add column counter_label text not null default 'Count';
alter table public.markets add column counter_value bigint not null default 0 check(counter_value>=0);
alter table public.markets add column counter_updated_at timestamptz;
create table public.counter_events(request_id uuid primary key,market_id uuid not null references public.markets(id),user_id uuid not null references public.profiles(id),delta integer not null check(delta<>0),created_at timestamptz not null default now());
alter table public.counter_events enable row level security;
create index counter_events_market_time_idx on public.counter_events(market_id,created_at);
create index counter_events_user_idx on public.counter_events(user_id);
create policy members_counter_events on public.counter_events for select to authenticated using((select private.is_member()));
revoke all on public.counter_events from public,anon,authenticated;
grant select on public.counter_events to authenticated;
create trigger immutable_counter_events before update or delete on public.counter_events for each row execute function private.immutable_record();

create function private.trigger_emergency() returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();s public.emergency_signal;
begin
 perform pg_advisory_xact_lock(84271001);
 select * into s from public.emergency_signal where id=1 for update;
 if s.triggered_at>clock_timestamp()-interval '5 seconds' then return s.version;end if;
 update public.emergency_signal set version=version+1,triggered_at=clock_timestamp() where id=1 returning * into s;
 insert into public.admin_events(actor_id,action,reason,details) values(uid,'emergency_redirect','Shared school-page redirect',jsonb_build_object('version',s.version));
 return s.version;
end $$;
create function private.set_counter_enabled(p_market uuid,p_enabled boolean,p_label text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();m public.markets;
begin
 perform pg_advisory_xact_lock(84271001);
 select * into m from public.markets where id=p_market for update;
 if not found then raise exception 'Unknown market';end if;
 if uid<>m.creator_id and not private.is_admin() then raise exception 'Only the creator or an admin can configure the counter';end if;
 if m.status='resolved' or m.archived then raise exception 'Market is closed';end if;
 if p_enabled is null then raise exception 'Choose a counter setting';end if;
 update public.markets set counter_enabled=p_enabled,counter_label=coalesce(nullif(trim(p_label),''),'Count') where id=p_market;
 insert into public.admin_events(actor_id,action,target_id,reason,details) values(uid,'counter_setting',p_market::text,'Live counter updated',jsonb_build_object('enabled',p_enabled));
end $$;
create function private.change_counter(p_market uuid,p_delta integer,p_request uuid) returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();m public.markets;existing public.counter_events;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null or p_delta is null or p_delta=0 or p_delta < -100000 or p_delta > 100000 then raise exception 'Invalid counter change';end if;
 select * into existing from public.counter_events where request_id=p_request;
 if found then
  if existing.user_id<>uid or existing.market_id<>p_market or existing.delta<>p_delta then raise exception 'Request ID already used';end if;
  return (select counter_value from public.markets where id=p_market);
 end if;
 select * into m from public.markets where id=p_market for update;
 if not found or not m.counter_enabled then raise exception 'Counter is not enabled';end if;
 if m.status='resolved' or m.archived then raise exception 'Market is closed';end if;
 if not private.is_admin() then
  if p_delta<>1 then raise exception 'Only admins can correct a count';end if;
  if m.status<>'open' or m.paused or m.closes_at<=now() then raise exception 'Counting is closed';end if;
 end if;
 if m.counter_value+p_delta<0 then raise exception 'The count cannot be negative';end if;
 update public.markets set counter_value=counter_value+p_delta,counter_updated_at=clock_timestamp() where id=p_market returning * into m;
 insert into public.counter_events(request_id,market_id,user_id,delta) values(p_request,p_market,uid,p_delta);
 return m.counter_value;
end $$;
create function private.create_market_v4(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer,p_counter boolean,p_counter_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare mid uuid;
begin
 mid:=private.create_market_v3(p_title,p_yes,p_no,p_closes,p_liquidity,p_verifications);
 if coalesce(p_counter,false) then perform private.set_counter_enabled(mid,true,p_counter_label);end if;
 return mid;
end $$;
create function public.trigger_emergency() returns bigint language sql security invoker set search_path='' as $$select private.trigger_emergency()$$;
create function public.set_counter_enabled(p_market uuid,p_enabled boolean,p_label text) returns void language sql security invoker set search_path='' as $$select private.set_counter_enabled(p_market,p_enabled,p_label)$$;
create function public.change_counter(p_market uuid,p_delta integer,p_request uuid) returns bigint language sql security invoker set search_path='' as $$select private.change_counter(p_market,p_delta,p_request)$$;
create function public.create_market_v4(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer,p_counter boolean,p_counter_label text) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v4(p_title,p_yes,p_no,p_closes,p_liquidity,p_verifications,p_counter,p_counter_label)$$;
revoke all on function private.trigger_emergency(),private.set_counter_enabled(uuid,boolean,text),private.change_counter(uuid,integer,uuid),private.create_market_v4(text,text,text,timestamptz,numeric,integer,boolean,text),public.trigger_emergency(),public.set_counter_enabled(uuid,boolean,text),public.change_counter(uuid,integer,uuid),public.create_market_v4(text,text,text,timestamptz,numeric,integer,boolean,text) from public,anon,authenticated;
grant execute on function private.trigger_emergency(),private.set_counter_enabled(uuid,boolean,text),private.change_counter(uuid,integer,uuid),private.create_market_v4(text,text,text,timestamptz,numeric,integer,boolean,text),public.trigger_emergency(),public.set_counter_enabled(uuid,boolean,text),public.change_counter(uuid,integer,uuid),public.create_market_v4(text,text,text,timestamptz,numeric,integer,boolean,text) to authenticated;
alter publication supabase_realtime add table public.emergency_signal,public.counter_events;

-- Retain historical deployment metadata, but retire unused wallet setup APIs.
drop function public.set_chain(text,text);
drop function private.set_chain(text,text);
