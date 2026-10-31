-- Preserve existing wallets, positions and prices. Credits remain virtual.
alter table public.profiles add column nickname text not null default '' check(length(nickname)<=40);
alter table public.profiles add column active boolean not null default true;
alter table public.markets add column paused boolean not null default false;
alter table public.markets add column archived boolean not null default false;
alter table public.markets add column admin_resolved boolean not null default false;
alter table public.markets alter column liquidity set default 400;
create table private.admins(user_id uuid primary key references public.profiles(id));
alter table private.admins enable row level security;
create table private.credit_accounts(id text primary key,balance numeric not null check(balance>=0));
alter table private.credit_accounts enable row level security;
create table private.economy(id integer primary key check(id=1),total_supply numeric not null check(total_supply>=0));
alter table private.economy enable row level security;
create table public.audit_blocks(seq bigint primary key,previous_hash text not null,hash text not null unique,payload text not null,created_at timestamptz not null default now());
create table public.admin_events(id uuid primary key default gen_random_uuid(),actor_id uuid not null references public.profiles(id),action text not null,target_id text,reason text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
create table public.chain_config(id integer primary key check(id=1),chain_id integer not null default 11155111 check(chain_id=11155111),address text check(address ~ '^0x[0-9a-fA-F]{40}$'),deployment_tx text check(deployment_tx ~ '^0x[0-9a-fA-F]{64}$'));
insert into public.chain_config(id) values(1);
alter table public.audit_blocks enable row level security;
alter table public.admin_events enable row level security;
alter table public.chain_config enable row level security;
create index admin_events_actor_idx on public.admin_events(actor_id);

create or replace function private.is_member() returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.profiles where id=auth.uid() and active) $$;
create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
select private.is_member() and exists(select 1 from private.admins where user_id=auth.uid()) $$;
create function private.require_admin() returns uuid language plpgsql stable security definer set search_path='' as $$
begin if not private.is_admin() then raise exception 'Admin access required'; end if;return auth.uid();end $$;
create function private.account_key(p_id text) returns text language sql immutable set search_path='' as $$
select encode(extensions.digest(p_id,'sha256'),'hex') $$;
create function private.audit_append(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare prev text; n bigint; body text;
begin
 perform pg_advisory_xact_lock(84271001);
 select seq,hash into n,prev from public.audit_blocks order by seq desc limit 1;
 n:=coalesce(n,0)+1;prev:=coalesce(prev,repeat('0',64));
 body:=(p_data||jsonb_build_object('seq',n,'previous_hash',prev))::text;
 insert into public.audit_blocks(seq,previous_hash,hash,payload) values(n,prev,encode(extensions.digest(body,'sha256'),'hex'),body);
end $$;
create function private.transfer(p_from text,p_to text,p_amount numeric,p_reason text,p_market uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(84271001);
 if p_amount=0 then return;end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0 or p_from=p_to then raise exception 'Invalid transfer';end if;
 update private.credit_accounts set balance=balance-p_amount where id=p_from and balance>=p_amount;
 if not found then raise exception 'Insufficient funded reserves';end if;
 update private.credit_accounts set balance=balance+p_amount where id=p_to;
 if not found then raise exception 'Unknown destination';end if;
 perform private.audit_append(jsonb_build_object('kind','transfer','from',private.account_key(p_from),'to',private.account_key(p_to),'amount',p_amount::text,'reason',p_reason,'market',case when p_market is not null then private.account_key(p_market::text) end));
end $$;

-- The genesis explicitly records a 100,000-credit supply and the legacy snapshot.
insert into private.economy values(1,100000);
insert into private.credit_accounts select 'user:'||user_id,balance from public.wallets;
insert into private.credit_accounts select 'market:'||id,case when status='resolved' then 0 else private.cost(q_yes,q_no,liquidity) end from public.markets;
insert into private.credit_accounts values('treasury',100000-(select coalesce(sum(balance),0) from private.credit_accounts));
select private.audit_append(jsonb_build_object('kind','genesis','total_supply','100000','accounts',(select jsonb_agg(jsonb_build_object('account',private.account_key(id),'balance',balance::text) order by id) from private.credit_accounts),'legacy_ledger_hash',(select encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(l) order by l.created_at,l.id)::text,'[]'),'sha256'),'hex') from public.ledger l)));

create function private.wallet_created() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into private.credit_accounts values('user:'||new.user_id,0);return new;end $$;
create trigger wallet_account after insert on public.wallets for each row execute function private.wallet_created();
create function private.market_created() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.credit_accounts values('market:'||new.id,0);
 perform private.transfer('treasury','market:'||new.id,private.cost(0,0,new.liquidity),'Market reserve',new.id);return new;
end $$;
create trigger market_account after insert on public.markets for each row execute function private.market_created();
create function private.record_ledger_transfer() returns trigger language plpgsql security definer set search_path='' as $$
declare other text;
begin
 other:=case when new.market_id is null then 'treasury' else 'market:'||new.market_id end;
 if new.amount>0 then perform private.transfer(other,'user:'||new.user_id,new.amount,new.reason,new.market_id);
 elsif new.amount<0 then perform private.transfer('user:'||new.user_id,other,-new.amount,new.reason,new.market_id);end if;
 return new;
end $$;
create trigger ledger_transfer after insert on public.ledger for each row execute function private.record_ledger_transfer();
create function private.release_market_reserve() returns trigger language plpgsql security definer set search_path='' as $$
declare remaining numeric;
begin
 if new.status='resolved' and old.status<>'resolved' then
  select balance into remaining from private.credit_accounts where id='market:'||new.id;
  perform private.transfer('market:'||new.id,'treasury',remaining,'Unused reserve',new.id);
 end if;return new;
end $$;
create trigger release_reserve after update of status on public.markets for each row execute function private.release_market_reserve();

-- Commit-time conservation checks cover every wallet/reserve mutation.
create function private.check_conservation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select sum(balance) from private.credit_accounts)<>(select total_supply from private.economy where id=1) then raise exception 'Credit supply does not reconcile';end if;
 if exists(select 1 from public.wallets w left join private.credit_accounts a on a.id='user:'||w.user_id where a.balance is distinct from w.balance) then raise exception 'Wallet ledger mismatch';end if;
 if exists(select 1 from public.markets m join private.credit_accounts a on a.id='market:'||m.id where m.status<>'resolved' and a.balance<greatest(m.q_yes,m.q_no)) then raise exception 'Market is not fully funded';end if;
 return null;
end $$;
create constraint trigger check_accounts after insert or update on private.credit_accounts deferrable initially deferred for each row execute function private.check_conservation();
create constraint trigger check_wallets after insert or update on public.wallets deferrable initially deferred for each row execute function private.check_conservation();
create constraint trigger check_supply after update on private.economy deferrable initially deferred for each row execute function private.check_conservation();

-- Keep authoritative pricing, positions and idempotency from v1; wrap access checks.
alter function private.trade(uuid,text,text,numeric,numeric,uuid) rename to trade_v1;
create function private.trade(p_market uuid,p_side text,p_action text,p_shares numeric,p_limit numeric,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.require_member();perform pg_advisory_xact_lock(84271001);
 if exists(select 1 from public.markets where id=p_market and (paused or archived)) then raise exception 'Market is paused';end if;
 return private.trade_v1(p_market,p_side,p_action,p_shares,p_limit,p_request);
end $$;
create or replace function private.create_market(p_title text,p_description text,p_category text,p_emoji text,p_closes timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_closes is null or p_closes<=now() or p_closes>now()+interval '1 year' then raise exception 'Choose a future closing time within one year';end if;
 if (select count(*) from public.markets where creator_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached';end if;
 insert into public.markets(creator_id,title,description,category,emoji,closes_at) values(uid,trim(p_title),trim(p_description),p_category,'',p_closes) returning id into mid;return mid;
end $$;
create function private.create_market_v2(p_title text,p_description text,p_category text,p_closes timestamptz,p_liquidity numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_liquidity is null or p_liquidity not in (100,200,400) then raise exception 'Invalid price sensitivity';end if;
 if p_closes is null or p_closes<=now() or p_closes>now()+interval '1 year' then raise exception 'Choose a future closing time within one year';end if;
 if (select count(*) from public.markets where creator_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached';end if;
 insert into public.markets(creator_id,title,description,category,emoji,closes_at,liquidity) values(uid,trim(p_title),trim(p_description),p_category,'',p_closes,p_liquidity) returning id into mid;return mid;
end $$;

create function private.sync_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare uname text:=split_part(new.email,'@',1); nick text:=coalesce(new.raw_user_meta_data->>'nickname','');
begin
 if new.email is distinct from old.email then
  if new.email <> uname||'@members.multimarche.invalid' or uname !~ '^[a-z0-9_]{3,24}$' then raise exception 'Invalid username email';end if;
  update public.profiles set username=uname where id=new.id;
 end if;
 update public.profiles set nickname=left(trim(nick),40) where id=new.id;return new;
end $$;
create trigger sync_member_profile after update of email,raw_user_meta_data on auth.users for each row execute function private.sync_profile();

create function private.admin_credit(p_user uuid,p_amount numeric,p_reason text,p_request uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();
begin
 perform pg_advisory_xact_lock(84271001);
 if exists(select 1 from public.admin_events where id=p_request and actor_id=uid and action='credit') then return;end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount>100000 or length(trim(p_reason))<5 or p_request is null then raise exception 'Invalid credit allocation';end if;
 update public.wallets set balance=balance+p_amount where user_id=p_user;
 if not found then raise exception 'Unknown member';end if;
 insert into public.ledger(user_id,amount,reason) values(p_user,p_amount,'Admin allocation: '||trim(p_reason));
 insert into public.admin_events(id,actor_id,action,target_id,reason,details) values(p_request,uid,'credit',p_user::text,p_reason,jsonb_build_object('amount',p_amount));
end $$;
create function private.admin_mint(p_amount numeric,p_reason text,p_request uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();
begin
 perform pg_advisory_xact_lock(84271001);
 if exists(select 1 from public.admin_events where id=p_request and actor_id=uid and action='mint') then return;end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount>1000000 or length(trim(p_reason))<5 or p_request is null then raise exception 'Invalid issuance';end if;
 update private.credit_accounts set balance=balance+p_amount where id='treasury';
 update private.economy set total_supply=total_supply+p_amount where id=1;
 perform private.audit_append(jsonb_build_object('kind','mint','amount',p_amount::text,'to',private.account_key('treasury'),'total_supply',(select total_supply::text from private.economy where id=1)));
 insert into public.admin_events(id,actor_id,action,reason,details) values(p_request,uid,'mint',p_reason,jsonb_build_object('amount',p_amount));
end $$;
create function private.admin_market(p_market uuid,p_action text,p_data jsonb,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();m public.markets;pay record;o text;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_reason is null or length(trim(p_reason))<5 then raise exception 'A reason is required';end if;
 select * into m from public.markets where id=p_market for update;
 if not found then raise exception 'Unknown market';end if;
 if p_action='pause' and m.status<>'resolved' then update public.markets set paused=true where id=p_market;
 elsif p_action='resume' and m.status<>'resolved' then update public.markets set paused=false where id=p_market;
 elsif p_action='edit' and m.status<>'resolved' then
  update public.markets set title=coalesce(p_data->>'title',title),description=coalesce(p_data->>'description',description),closes_at=coalesce((p_data->>'closes_at')::timestamptz,closes_at) where id=p_market;
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
create function private.admin_invite(p_uses integer) returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();code text:='MM-'||encode(extensions.gen_random_bytes(12),'hex');
begin
 if p_uses is null or p_uses<1 or p_uses>100 then raise exception 'Choose 1–100 uses';end if;
 insert into private.invites values(encode(extensions.digest(code,'sha256'),'hex'),p_uses,now()+interval '30 days');
 insert into public.admin_events(actor_id,action,reason,details) values(uid,'invite','New invitation',jsonb_build_object('uses',p_uses));return code;
end $$;
create function private.set_chain(p_address text,p_tx text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_admin();
begin
 if p_address is null or p_tx is null then raise exception 'Contract and transaction are required';end if;
 if exists(select 1 from public.chain_config where address is not null and lower(address)<>lower(p_address)) then raise exception 'An audit contract is already configured';end if;
 update public.chain_config set address=p_address,deployment_tx=p_tx where id=1;
 insert into public.admin_events(actor_id,action,reason,details) values(uid,'chain_setup','Sepolia audit contract',jsonb_build_object('address',p_address,'transaction',p_tx));
end $$;
create function private.economy_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_member();return jsonb_build_object('total_supply',(select total_supply from private.economy where id=1),'treasury',(select balance from private.credit_accounts where id='treasury'),'wallets',(select coalesce(sum(balance),0) from public.wallets),'reserved',(select coalesce(sum(balance),0) from private.credit_accounts where id like 'market:%'),'height',(select coalesce(max(seq),0) from public.audit_blocks));end $$;
create function private.admin_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform private.require_admin();return (select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'nickname',p.nickname,'balance',w.balance,'admin',exists(select 1 from private.admins a where a.user_id=p.id))) from public.profiles p join public.wallets w on w.user_id=p.id);end $$;
create function private.verify_audit() returns boolean language plpgsql stable security definer set search_path='' as $$
declare b record;prev text:=repeat('0',64);n bigint:=1;
begin perform private.require_member();for b in select * from public.audit_blocks order by seq loop
 if b.seq<>n or b.previous_hash<>prev or b.hash<>encode(extensions.digest(b.payload,'sha256'),'hex') or (b.payload::jsonb->>'previous_hash')<>prev or (b.payload::jsonb->>'seq')::bigint<>n then return false;end if;
 prev:=b.hash;n:=n+1;end loop;return true;
end $$;
create function private.immutable_record() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'Audit records cannot be changed or deleted';end $$;
create trigger immutable_audit before update or delete on public.audit_blocks for each row execute function private.immutable_record();
create trigger immutable_admin before update or delete on public.admin_events for each row execute function private.immutable_record();
create policy read_audit on public.audit_blocks for select to authenticated using((select private.is_member()));
create policy read_admin_events on public.admin_events for select to authenticated using((select private.is_member()));
create policy read_chain on public.chain_config for select to authenticated using((select private.is_member()));
revoke all on public.audit_blocks,public.admin_events,public.chain_config from public,anon,authenticated;
grant select on public.audit_blocks,public.admin_events,public.chain_config to authenticated;

create function public.is_admin() returns boolean language sql security invoker set search_path='' as $$select private.is_admin()$$;
create function public.create_market_v2(p_title text,p_description text,p_category text,p_closes timestamptz,p_liquidity numeric) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v2(p_title,p_description,p_category,p_closes,p_liquidity)$$;
create function public.admin_credit(p_user uuid,p_amount numeric,p_reason text,p_request uuid) returns void language sql security invoker set search_path='' as $$select private.admin_credit(p_user,p_amount,p_reason,p_request)$$;
create function public.admin_mint(p_amount numeric,p_reason text,p_request uuid) returns void language sql security invoker set search_path='' as $$select private.admin_mint(p_amount,p_reason,p_request)$$;
create function public.admin_market(p_market uuid,p_action text,p_data jsonb,p_reason text) returns void language sql security invoker set search_path='' as $$select private.admin_market(p_market,p_action,p_data,p_reason)$$;
create function public.admin_invite(p_uses integer) returns text language sql security invoker set search_path='' as $$select private.admin_invite(p_uses)$$;
create function public.set_chain(p_address text,p_tx text) returns void language sql security invoker set search_path='' as $$select private.set_chain(p_address,p_tx)$$;
create function public.economy_status() returns jsonb language sql security invoker set search_path='' as $$select private.economy_status()$$;
create function public.admin_members() returns jsonb language sql security invoker set search_path='' as $$select private.admin_members()$$;
create function public.verify_audit() returns boolean language sql security invoker set search_path='' as $$select private.verify_audit()$$;
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_member(),private.require_member(),private.is_admin(),private.trade(uuid,text,text,numeric,numeric,uuid),private.create_market(text,text,text,text,timestamptz),private.resolve_market(uuid,text,text),private.withdraw_resolution(uuid),private.leaderboard(),private.create_market_v2(text,text,text,timestamptz,numeric),private.admin_credit(uuid,numeric,text,uuid),private.admin_mint(numeric,text,uuid),private.admin_market(uuid,text,jsonb,text),private.admin_invite(integer),private.set_chain(text,text),private.economy_status(),private.admin_members(),private.verify_audit() to authenticated;
revoke all on function public.is_admin(),public.create_market_v2(text,text,text,timestamptz,numeric),public.admin_credit(uuid,numeric,text,uuid),public.admin_mint(numeric,text,uuid),public.admin_market(uuid,text,jsonb,text),public.admin_invite(integer),public.set_chain(text,text),public.economy_status(),public.admin_members(),public.verify_audit() from public,anon;
grant execute on function public.is_admin(),public.create_market_v2(text,text,text,timestamptz,numeric),public.admin_credit(uuid,numeric,text,uuid),public.admin_mint(numeric,text,uuid),public.admin_market(uuid,text,jsonb,text),public.admin_invite(integer),public.set_chain(text,text),public.economy_status(),public.admin_members(),public.verify_audit() to authenticated;
alter publication supabase_realtime add table public.audit_blocks,public.admin_events,public.profiles;
