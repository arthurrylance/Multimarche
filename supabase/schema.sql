-- Multimarché: virtual credits only. Apply once to a fresh Supabase project.
create schema if not exists private;
create extension if not exists pgcrypto with schema extensions;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table private.invites (
  code_hash text primary key,
  remaining integer not null check (remaining >= 0),
  expires_at timestamptz not null
);
alter table private.invites enable row level security;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,24}$'),
  created_at timestamptz not null default now()
);
create table public.wallets (
  user_id uuid primary key references public.profiles(id),
  balance numeric not null default 1000 check (balance >= 0)
);
create table public.markets (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id),
  title text not null check (length(title) between 10 and 160),
  description text not null check (length(description) between 20 and 3000),
  category text not null check (category in ('Classroom','Campus','Sports','Culture','Other')),
  emoji text not null default '🎯' check (length(emoji) <= 16),
  closes_at timestamptz not null,
  created_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open','proposed','resolved')),
  q_yes numeric not null default 0 check (q_yes >= 0),
  q_no numeric not null default 0 check (q_no >= 0),
  liquidity numeric not null default 100 check (liquidity > 0),
  probability double precision not null default 0.5 check (probability between 0 and 1),
  volume numeric not null default 0,
  outcome text check (outcome in ('yes','no','void')),
  resolved_at timestamptz
);
create table public.positions (
  user_id uuid not null references public.profiles(id),
  market_id uuid not null references public.markets(id),
  side text not null check (side in ('yes','no')),
  shares numeric not null check (shares >= 0),
  net_cost numeric not null default 0,
  primary key(user_id,market_id,side)
);
create table public.trades (
  id uuid primary key default gen_random_uuid(),
  request_id uuid unique not null,
  user_id uuid not null references public.profiles(id),
  market_id uuid not null references public.markets(id),
  side text not null check (side in ('yes','no')),
  action text not null check (action in ('buy','sell')),
  shares numeric not null,
  total numeric not null,
  probability double precision not null,
  created_at timestamptz not null default now()
);
create table public.resolution_votes (
  market_id uuid not null references public.markets(id),
  user_id uuid not null references public.profiles(id),
  outcome text not null check (outcome in ('yes','no','void')),
  evidence text not null check (length(evidence) between 10 and 2000),
  created_at timestamptz not null default now(),
  primary key(market_id,user_id)
);
create table public.ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  market_id uuid references public.markets(id),
  amount numeric not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.markets(id),
  user_id uuid not null references public.profiles(id),
  body text not null check (length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table public.watchlist (
  user_id uuid not null references public.profiles(id),
  market_id uuid not null references public.markets(id),
  primary key(user_id,market_id)
);
create index markets_creator_idx on public.markets(creator_id);
create index markets_closes_idx on public.markets(status,closes_at);
create index positions_market_idx on public.positions(market_id);
create index trades_market_time_idx on public.trades(market_id,created_at);
create index trades_user_idx on public.trades(user_id);
create index votes_user_idx on public.resolution_votes(user_id);
create index ledger_user_idx on public.ledger(user_id,created_at);
create index ledger_market_idx on public.ledger(market_id);
create index comments_market_idx on public.comments(market_id,created_at);
create index comments_user_idx on public.comments(user_id);
create index watchlist_market_idx on public.watchlist(market_id);

-- Private helper avoids recursive profile policies; no user-controlled authorization claims.
create function private.is_member() returns boolean language sql stable security definer
set search_path = '' as $$ select exists(select 1 from public.profiles where id = auth.uid()) $$;
create function private.require_member() returns uuid language plpgsql stable security definer
set search_path = '' as $$
begin
  if auth.uid() is null or not private.is_member() then raise exception 'Members only'; end if;
  return auth.uid();
end $$;

-- Auth trigger must run as owner: Auth inserts users before a JWT exists.
-- Invitation consumption and starting funds are in the same transaction as account creation.
create function private.on_signup() returns trigger language plpgsql security definer
set search_path = '' as $$
declare uname text := lower(new.raw_user_meta_data->>'username');
begin
  if uname is null or uname !~ '^[a-z0-9_]{3,24}$' then raise exception 'Invalid username'; end if;
  update private.invites set remaining = remaining - 1
    where code_hash = encode(extensions.digest(coalesce(new.raw_user_meta_data->>'invite',''),'sha256'),'hex')
      and remaining > 0 and expires_at > now();
  if not found then raise exception 'Invalid or expired invitation'; end if;
  insert into public.profiles(id,username) values(new.id,uname);
  insert into public.wallets(user_id) values(new.id);
  insert into public.ledger(user_id,amount,reason) values(new.id,1000,'Starting credits');
  -- Never retain the invitation in the user's metadata/JWT.
  update auth.users set raw_user_meta_data=jsonb_build_object('username',uname) where id=new.id;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function private.on_signup();

-- Numerically stable binary LMSR cost function.
create function private.cost(y numeric,n numeric,b numeric) returns numeric
language sql immutable set search_path = '' as $$
 select greatest(y,n) + b * ln(1 + exp(-abs(y-n)/b));
$$;
create function private.trade(p_market uuid,p_side text,p_action text,p_shares numeric,p_limit numeric,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); m public.markets; w public.wallets;
  delta numeric; total numeric; ny numeric; nn numeric; held numeric; existing public.trades;
begin
  -- One economy lock is deliberately simple and safe for a small closed group.
  perform pg_advisory_xact_lock(84271001);
  select * into existing from public.trades where request_id = p_request;
  if found then
    if existing.user_id <> uid or existing.market_id <> p_market or existing.side <> p_side or existing.action <> p_action or existing.shares <> p_shares then
      raise exception 'Request ID already used';
    end if;
    return jsonb_build_object('total',existing.total,'shares',existing.shares);
  end if;
  if p_side is null or p_side not in ('yes','no') or p_action is null or p_action not in ('buy','sell')
    or p_shares is null or p_shares::text in ('NaN','Infinity','-Infinity') or p_shares < 0.0001 or p_shares > 10000
    or p_limit is null or p_limit::text in ('NaN','Infinity','-Infinity') or p_limit < 0 or p_request is null then raise exception 'Invalid trade'; end if;
  select * into m from public.markets where id=p_market for update;
  if not found then raise exception 'Market not found'; end if;
  if m.status <> 'open' or m.closes_at <= now() then raise exception 'Trading is closed'; end if;
  select * into w from public.wallets where user_id=uid for update;
  select shares into held from public.positions where user_id=uid and market_id=p_market and side=p_side;
  if p_action='sell' and coalesce(held,0)<p_shares then raise exception 'Not enough shares'; end if;
  delta := case when p_action='buy' then p_shares else -p_shares end;
  ny := m.q_yes + case when p_side='yes' then delta else 0 end;
  nn := m.q_no + case when p_side='no' then delta else 0 end;
  total := abs(private.cost(ny,nn,m.liquidity)-private.cost(m.q_yes,m.q_no,m.liquidity));
  if total < 0.000001 then raise exception 'Trade too small'; end if;
  if p_action='buy' and (total>p_limit or total>w.balance) then raise exception 'Price changed or insufficient credits'; end if;
  if p_action='sell' and total<p_limit then raise exception 'Price changed; review your quote'; end if;
  update public.wallets set balance=balance + case when p_action='buy' then -total else total end where user_id=uid;
  insert into public.positions(user_id,market_id,side,shares,net_cost)
    values(uid,p_market,p_side,coalesce(held,0)+delta,case when p_action='buy' then total else -total end)
    on conflict(user_id,market_id,side) do update set shares=excluded.shares,net_cost=public.positions.net_cost+excluded.net_cost;
  update public.markets set q_yes=ny,q_no=nn,
    probability=(1/(1+exp(greatest(-700,least(700,(nn-ny)/m.liquidity)))))::double precision,
    volume=volume+total where id=p_market returning * into m;
  insert into public.trades(request_id,user_id,market_id,side,action,shares,total,probability)
    values(p_request,uid,p_market,p_side,p_action,p_shares,total,m.probability);
  insert into public.ledger(user_id,market_id,amount,reason) values(uid,p_market,case when p_action='buy' then -total else total end,p_action||' '||p_side);
  return jsonb_build_object('total',total,'shares',p_shares);
end $$;

create function private.create_market(p_title text,p_description text,p_category text,p_emoji text,p_closes timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); mid uuid;
begin
  if p_closes is null or p_closes<=now() or p_closes>now()+interval '1 year' then raise exception 'Choose a closing date within the next year'; end if;
  if (select count(*) from public.markets where creator_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached'; end if;
  insert into public.markets(creator_id,title,description,category,emoji,closes_at)
    values(uid,trim(p_title),trim(p_description),p_category,p_emoji,p_closes) returning id into mid;
  return mid;
end $$;

create function private.resolve_market(p_market uuid,p_outcome text,p_evidence text)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); m public.markets; previous text; payout record;
begin
  perform pg_advisory_xact_lock(84271001);
  if p_outcome is null or p_outcome not in ('yes','no','void') then raise exception 'Invalid outcome'; end if;
  select * into m from public.markets where id=p_market for update;
  if not found then raise exception 'Market not found'; end if;
  if m.status='resolved' then raise exception 'Already resolved'; end if;
  if exists(select 1 from public.resolution_votes where market_id=p_market and user_id=uid) then raise exception 'A second distinct member must confirm'; end if;
  select outcome into previous from public.resolution_votes where market_id=p_market limit 1;
  if previous is not null and previous<>p_outcome then raise exception 'Confirmation must match the proposed result'; end if;
  insert into public.resolution_votes(market_id,user_id,outcome,evidence) values(p_market,uid,p_outcome,trim(p_evidence));
  if previous is null then
    update public.markets set status='proposed',outcome=p_outcome where id=p_market;
    return 'proposed';
  end if;
  for payout in select user_id,sum(shares * case when p_outcome='void' then 0.5 when side=p_outcome then 1 else 0 end) amount
    from public.positions where market_id=p_market group by user_id order by user_id loop
    update public.wallets set balance=balance+payout.amount where user_id=payout.user_id;
    insert into public.ledger(user_id,market_id,amount,reason) values(payout.user_id,p_market,payout.amount,'Settlement: '||p_outcome);
  end loop;
  update public.markets set status='resolved',outcome=p_outcome,resolved_at=now(),
    probability=case p_outcome when 'yes' then 1 when 'no' then 0 else 0.5 end where id=p_market;
  return 'resolved';
end $$;
create function private.withdraw_resolution(p_market uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  perform pg_advisory_xact_lock(84271001);
  if not exists(select 1 from public.markets where id=p_market and status='proposed') then raise exception 'No pending proposal'; end if;
  delete from public.resolution_votes where market_id=p_market and user_id=uid;
  if not found then raise exception 'Only the proposer can withdraw'; end if;
  update public.markets set status='open',outcome=null where id=p_market;
end $$;
create function private.leaderboard() returns table(id uuid,username text,equity numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_member();
  return query select p.id,p.username,w.balance+coalesce((select sum(pos.shares * case when pos.side='yes' then m.probability else 1-m.probability end)
    from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and m.status<>'resolved'),0)::numeric
    from public.profiles p join public.wallets w on w.user_id=p.id order by 3 desc;
end $$;

-- Thin invoker APIs delegate to private transaction functions. No direct economy writes.
create function public.trade(p_market uuid,p_side text,p_action text,p_shares numeric,p_limit numeric,p_request uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.trade(p_market,p_side,p_action,p_shares,p_limit,p_request) $$;
create function public.create_market(p_title text,p_description text,p_category text,p_emoji text,p_closes timestamptz) returns uuid
language sql security invoker set search_path = '' as $$ select private.create_market(p_title,p_description,p_category,p_emoji,p_closes) $$;
create function public.resolve_market(p_market uuid,p_outcome text,p_evidence text) returns text
language sql security invoker set search_path = '' as $$ select private.resolve_market(p_market,p_outcome,p_evidence) $$;
create function public.withdraw_resolution(p_market uuid) returns void
language sql security invoker set search_path = '' as $$ select private.withdraw_resolution(p_market) $$;
create function public.leaderboard() returns table(id uuid,username text,equity numeric)
language sql security invoker set search_path = '' as $$ select * from private.leaderboard() $$;

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.markets enable row level security;
alter table public.positions enable row level security;
alter table public.trades enable row level security;
alter table public.resolution_votes enable row level security;
alter table public.ledger enable row level security;
alter table public.comments enable row level security;
alter table public.watchlist enable row level security;
create policy members_profiles on public.profiles for select to authenticated using ((select private.is_member()));
create policy members_markets on public.markets for select to authenticated using ((select private.is_member()));
create policy members_trades on public.trades for select to authenticated using ((select private.is_member()));
create policy members_votes on public.resolution_votes for select to authenticated using ((select private.is_member()));
create policy members_comments on public.comments for select to authenticated using ((select private.is_member()));
create policy own_wallet on public.wallets for select to authenticated using (user_id=(select auth.uid()) and (select private.is_member()));
create policy own_positions on public.positions for select to authenticated using (user_id=(select auth.uid()) and (select private.is_member()));
create policy own_ledger on public.ledger for select to authenticated using (user_id=(select auth.uid()) and (select private.is_member()));
create policy own_watchlist on public.watchlist for all to authenticated using (user_id=(select auth.uid()) and (select private.is_member())) with check (user_id=(select auth.uid()) and (select private.is_member()));
create policy add_comment on public.comments for insert to authenticated with check (user_id=(select auth.uid()) and (select private.is_member()));
revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.wallets,public.markets,public.positions,public.trades,public.resolution_votes,public.ledger,public.comments,public.watchlist to authenticated;
grant insert on public.comments to authenticated;
grant insert,delete on public.watchlist to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
revoke all on function public.trade(uuid,text,text,numeric,numeric,uuid),public.create_market(text,text,text,text,timestamptz),public.resolve_market(uuid,text,text),public.withdraw_resolution(uuid),public.leaderboard() from public,anon;
grant execute on function private.is_member(),private.require_member(),private.trade(uuid,text,text,numeric,numeric,uuid),private.create_market(text,text,text,text,timestamptz),private.resolve_market(uuid,text,text),private.withdraw_resolution(uuid),private.leaderboard() to authenticated;
grant execute on function public.trade(uuid,text,text,numeric,numeric,uuid),public.create_market(text,text,text,text,timestamptz),public.resolve_market(uuid,text,text),public.withdraw_resolution(uuid),public.leaderboard() to authenticated;
alter publication supabase_realtime add table public.markets,public.trades,public.wallets,public.positions,public.resolution_votes,public.comments,public.watchlist;
