alter table public.markets drop constraint markets_title_check;
alter table public.markets add constraint markets_title_check check(length(btrim(title))>0);
alter table public.markets drop constraint markets_description_check;
alter table public.resolution_votes drop constraint resolution_votes_evidence_check;
alter table public.markets add column yes_rule text not null default '';
alter table public.markets add column no_rule text not null default '';
alter table public.markets add column required_verifications integer not null default 2 check(required_verifications>=2);
alter table public.markets add column state_changed_at timestamptz not null default now();
update public.markets set yes_rule=description,no_rule='The event does not happen as described.',state_changed_at=coalesce(resolved_at,created_at);

create table public.notification_reads(user_id uuid not null references public.profiles(id),event_key text not null,read_at timestamptz not null default now(),primary key(user_id,event_key));
alter table public.notification_reads enable row level security;
create policy own_notification_reads on public.notification_reads for select to authenticated using(user_id=(select auth.uid()) and (select private.is_member()));
create policy insert_notification_reads on public.notification_reads for insert to authenticated with check(user_id=(select auth.uid()) and (select private.is_member()));
revoke all on public.notification_reads from public,anon,authenticated;
grant select,insert on public.notification_reads to authenticated;

create function private.market_state_timestamp() returns trigger language plpgsql set search_path='' as $$
begin if new.status is distinct from old.status or new.outcome is distinct from old.outcome then new.state_changed_at:=clock_timestamp();end if;return new;end $$;
create trigger market_state_time before update of status,outcome on public.markets for each row execute function private.market_state_timestamp();

create function private.create_market_v3(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 if nullif(trim(p_title),'') is null or nullif(trim(p_yes),'') is null or nullif(trim(p_no),'') is null then raise exception 'Question and Yes/No meanings are required';end if;
 if p_liquidity is null or p_liquidity not in (100,200,400) then raise exception 'Invalid price sensitivity';end if;
 if p_verifications is null or p_verifications<2 then raise exception 'At least two confirmations are required';end if;
 if p_closes is null or p_closes<=now() or p_closes>now()+interval '1 year' then raise exception 'Choose a future closing time within one year';end if;
 if (select count(*) from public.markets where creator_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached';end if;
 insert into public.markets(creator_id,title,description,category,emoji,closes_at,liquidity,yes_rule,no_rule,required_verifications)
 values(uid,trim(p_title),'Yes: '||trim(p_yes)||E'\nNo: '||trim(p_no),'Other','',p_closes,p_liquidity,trim(p_yes),trim(p_no),p_verifications) returning id into mid;return mid;
end $$;

create or replace function private.resolve_market(p_market uuid,p_outcome text,p_evidence text) returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();m public.markets;previous text; confirmations integer;pay record;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_outcome is null or p_outcome not in ('yes','no','void') then raise exception 'Invalid outcome';end if;
 select * into m from public.markets where id=p_market for update;
 if not found then raise exception 'Market not found';end if;
 if m.status='resolved' then raise exception 'Already resolved';end if;
 if exists(select 1 from public.resolution_votes where market_id=p_market and user_id=uid) then raise exception 'Each member can confirm once';end if;
 select outcome into previous from public.resolution_votes where market_id=p_market limit 1;
 if previous is not null and previous<>p_outcome then raise exception 'Confirmation must match the proposed result';end if;
 insert into public.resolution_votes(market_id,user_id,outcome,evidence) values(p_market,uid,p_outcome,coalesce(trim(p_evidence),''));
 select count(*) into confirmations from public.resolution_votes where market_id=p_market and outcome=p_outcome;
 if confirmations<m.required_verifications then
  update public.markets set status='proposed',outcome=p_outcome where id=p_market;return 'proposed';
 end if;
 for pay in select user_id,sum(shares*case when p_outcome='void' then .5 when side=p_outcome then 1 else 0 end) amount from public.positions where market_id=p_market group by user_id order by user_id loop
  update public.wallets set balance=balance+pay.amount where user_id=pay.user_id;
  insert into public.ledger(user_id,market_id,amount,reason) values(pay.user_id,p_market,pay.amount,'Settlement: '||p_outcome);
 end loop;
 update public.markets set status='resolved',outcome=p_outcome,resolved_at=now(),probability=case p_outcome when 'yes' then 1 when 'no' then 0 else .5 end where id=p_market;return 'resolved';
end $$;

create or replace function private.admin_market(p_market uuid,p_action text,p_data jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();m public.markets;pay record;o text;yr text;nr text;
begin
 perform pg_advisory_xact_lock(84271001);
 p_reason:=coalesce(nullif(trim(p_reason),''),'Admin '||p_action);
 select * into m from public.markets where id=p_market for update;
 if not found then raise exception 'Unknown market';end if;
 if p_action='pause' and m.status<>'resolved' then update public.markets set paused=true where id=p_market;
 elsif p_action='resume' and m.status<>'resolved' then update public.markets set paused=false where id=p_market;
 elsif p_action='edit' and m.status<>'resolved' then
  yr:=coalesce(p_data->>'yes_rule',p_data->>'description',m.yes_rule);nr:=coalesce(p_data->>'no_rule',m.no_rule);
  if nullif(trim(coalesce(p_data->>'title',m.title)),'') is null or nullif(trim(yr),'') is null or nullif(trim(nr),'') is null then raise exception 'Question and Yes/No meanings are required';end if;
  update public.markets set title=coalesce(p_data->>'title',title),yes_rule=yr,no_rule=nr,description='Yes: '||yr||E'\nNo: '||nr,closes_at=coalesce((p_data->>'closes_at')::timestamptz,closes_at) where id=p_market;
 elsif p_action='settle' and m.status<>'resolved' then
  o:=p_data->>'outcome';if o is null or o not in ('yes','no','void') then raise exception 'Invalid outcome';end if;
  for pay in select user_id,sum(shares*case when o='void' then .5 when side=o then 1 else 0 end) amount from public.positions where market_id=p_market group by user_id order by user_id loop
   update public.wallets set balance=balance+pay.amount where user_id=pay.user_id;
   insert into public.ledger(user_id,market_id,amount,reason) values(pay.user_id,p_market,pay.amount,'Settlement: '||o);
  end loop;
  update public.markets set status='resolved',outcome=o,resolved_at=now(),admin_resolved=true,probability=case o when 'yes' then 1 when 'no' then 0 else .5 end where id=p_market;
 elsif p_action='archive' and m.status='resolved' then update public.markets set archived=true where id=p_market;
 else raise exception 'Action not allowed for this market state';end if;
 insert into public.admin_events(actor_id,action,target_id,reason,details) values(uid,'market_'||p_action,p_market::text,p_reason,jsonb_build_object('before',to_jsonb(m),'change',p_data));
end $$;

create function private.admin_set_role(p_user uuid,p_admin boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();already boolean;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_admin is null or not exists(select 1 from public.profiles where id=p_user and active) then raise exception 'Choose an active member';end if;
 select exists(select 1 from private.admins where user_id=p_user) into already;
 if already=p_admin then return;end if;
 if p_admin then insert into private.admins values(p_user);
 else
  if (select count(*) from private.admins a join public.profiles p on p.id=a.user_id where p.active)<=1 then raise exception 'At least one admin must remain';end if;
  delete from private.admins where user_id=p_user;
 end if;
 insert into public.admin_events(actor_id,action,target_id,reason,details) values(uid,case when p_admin then 'admin_granted' else 'admin_removed' end,p_user::text,case when p_admin then 'Admin access granted' else 'Admin access removed' end,jsonb_build_object('admin',p_admin));
end $$;
create or replace function private.admin_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_admin();return (select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'nickname',p.nickname,'active',p.active,'balance',w.balance,'admin',exists(select 1 from private.admins a where a.user_id=p.id)) order by p.username) from public.profiles p join public.wallets w on w.user_id=p.id);end $$;
create function public.create_market_v3(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v3(p_title,p_yes,p_no,p_closes,p_liquidity,p_verifications)$$;
create function public.admin_set_role(p_user uuid,p_admin boolean) returns void language sql security invoker set search_path='' as $$select private.admin_set_role(p_user,p_admin)$$;
revoke all on function private.market_state_timestamp(),private.create_market_v3(text,text,text,timestamptz,numeric,integer),private.admin_set_role(uuid,boolean),public.create_market_v3(text,text,text,timestamptz,numeric,integer),public.admin_set_role(uuid,boolean) from public,anon,authenticated;
grant execute on function private.create_market_v3(text,text,text,timestamptz,numeric,integer),private.admin_set_role(uuid,boolean),public.create_market_v3(text,text,text,timestamptz,numeric,integer),public.admin_set_role(uuid,boolean) to authenticated;
