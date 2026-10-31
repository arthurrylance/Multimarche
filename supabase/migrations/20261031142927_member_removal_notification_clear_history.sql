-- Access is revoked before Auth cleanup, preserving all funded credit history.
alter table public.profiles add column deleted_at timestamptz;
alter table public.profiles add column auth_deleted_at timestamptz;
create function private.admin_delete_member(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();target public.profiles;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_user=uid then raise exception 'You cannot delete your own account';end if;
 select * into target from public.profiles where id=p_user for update;
 if not found then raise exception 'Unknown member';end if;
 if target.deleted_at is not null then return;end if;
 if exists(select 1 from private.admins where user_id=p_user) and (select count(*) from private.admins a join public.profiles p on p.id=a.user_id where p.active)<=1 then raise exception 'At least one admin must remain';end if;
 delete from private.admins where user_id=p_user;
 update public.profiles set active=false,deleted_at=clock_timestamp() where id=p_user;
 insert into public.admin_events(actor_id,action,target_id,reason) values(uid,'member_deleted',p_user::text,'Member login removed; financial and market history retained');
end $$;

-- Auth soft-deletion clears identity metadata. Leave historical profile names intact.
create or replace function private.sync_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare uname text:=split_part(new.email,'@',1);nick text:=coalesce(new.raw_user_meta_data->>'nickname','');
begin
 if exists(select 1 from public.profiles where id=new.id and not active) then return new;end if;
 if new.email is distinct from old.email then
  if new.email <> uname||'@members.multimarche.invalid' or uname !~ '^[a-z0-9_]{3,24}$' then raise exception 'Invalid username email';end if;
  update public.profiles set username=uname where id=new.id;
 end if;
 update public.profiles set nickname=left(trim(nick),40) where id=new.id;return new;
end $$;
create or replace function private.leaderboard() returns table(id uuid,username text,equity numeric) language plpgsql stable security definer set search_path='' as $$
begin
 perform private.require_member();
 return query select p.id,p.username,w.balance+coalesce((select sum(pos.shares*case when pos.side='yes' then m.probability else 1-m.probability end) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and m.status<>'resolved'),0)::numeric from public.profiles p join public.wallets w on w.user_id=p.id where p.active order by 3 desc;
end $$;
create or replace function private.admin_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_admin();return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'nickname',p.nickname,'active',p.active,'deleted_at',p.deleted_at,'auth_deleted_at',p.auth_deleted_at,'balance',w.balance,'admin',exists(select 1 from private.admins a where a.user_id=p.id)) order by p.username) from public.profiles p join public.wallets w on w.user_id=p.id),'[]'::jsonb);end $$;

alter table public.notification_reads add column dismissed boolean not null default false;
create function private.acknowledge_notifications(p_keys text[],p_clear boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();
begin
 if p_keys is null or cardinality(p_keys)>1000 or p_clear is null or exists(select 1 from unnest(p_keys) k where k is null or length(k)>500 or length(k)=0) then raise exception 'Invalid notifications';end if;
 insert into public.notification_reads(user_id,event_key,dismissed) select uid,k,p_clear from (select distinct unnest(p_keys) k) keys
 on conflict(user_id,event_key) do update set dismissed=public.notification_reads.dismissed or excluded.dismissed;
end $$;
alter publication supabase_realtime add table public.notification_reads;

-- Complete market history, including archived markets and removed members.
create function private.market_history(p_market uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.markets;traders jsonb;votes jsonb;override jsonb;
begin
 perform private.require_member();select * into m from public.markets where id=p_market;
 if not found or m.status<>'resolved' then raise exception 'Choose a resolved market';end if;
 with trading as (
  select user_id,coalesce(sum(total) filter(where action='buy'),0) spent,coalesce(sum(total) filter(where action='sell'),0) received from public.trades where market_id=p_market group by user_id
 ), holdings as (
  select user_id,coalesce(sum(shares) filter(where side='yes'),0) yes_shares,coalesce(sum(shares) filter(where side='no'),0) no_shares from public.positions where market_id=p_market group by user_id
 ), results as (
  select coalesce(t.user_id,h.user_id) user_id,coalesce(t.spent,0) spent,coalesce(t.received,0) received,coalesce(h.yes_shares,0) yes_shares,coalesce(h.no_shares,0) no_shares,
   case m.outcome when 'yes' then coalesce(h.yes_shares,0) when 'no' then coalesce(h.no_shares,0) else (coalesce(h.yes_shares,0)+coalesce(h.no_shares,0))*.5 end payout
  from trading t full join holdings h on h.user_id=t.user_id
 ) select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('profit',r.received+r.payout-r.spent) order by r.user_id),'[]'::jsonb) into traders from results r;
 select coalesce(jsonb_agg(to_jsonb(v) order by v.created_at,v.user_id),'[]'::jsonb) into votes from public.resolution_votes v where market_id=p_market;
 if m.admin_resolved then select jsonb_build_object('user_id',actor_id,'reason',reason,'created_at',created_at) into override from public.admin_events where target_id=p_market::text and action='market_settle' order by created_at desc limit 1;end if;
 return jsonb_build_object('traders',traders,'votes',votes,'admin_resolution',override);
end $$;
create function public.is_member() returns boolean language sql security invoker set search_path='' as $$select private.is_member()$$;
create function public.admin_delete_member(p_user uuid) returns void language sql security invoker set search_path='' as $$select private.admin_delete_member(p_user)$$;
create function public.acknowledge_notifications(p_keys text[],p_clear boolean) returns void language sql security invoker set search_path='' as $$select private.acknowledge_notifications(p_keys,p_clear)$$;
create function public.market_history(p_market uuid) returns jsonb language sql security invoker set search_path='' as $$select private.market_history(p_market)$$;
revoke all on function private.admin_delete_member(uuid),private.acknowledge_notifications(text[],boolean),private.market_history(uuid),public.is_member(),public.admin_delete_member(uuid),public.acknowledge_notifications(text[],boolean),public.market_history(uuid) from public,anon,authenticated;
grant execute on function private.admin_delete_member(uuid),private.acknowledge_notifications(text[],boolean),private.market_history(uuid),public.is_member(),public.admin_delete_member(uuid),public.acknowledge_notifications(text[],boolean),public.market_history(uuid) to authenticated;
