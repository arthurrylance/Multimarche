-- Existing markets retain the AMM. Every public creation endpoint now creates a CLOB.
alter table public.markets add column execution_model text not null default 'amm' check(execution_model in ('amm','clob'));
alter table public.markets add column price_available boolean not null default true;
alter table public.markets add column last_trade_price numeric;
alter table public.markets add column book_version bigint not null default 0;
alter table public.wallets add column reserved_balance numeric not null default 0 check(reserved_balance>=0 and reserved_balance<=balance);
alter table public.positions add column reserved_shares numeric not null default 0 check(reserved_shares>=0 and reserved_shares<=shares);
create table public.orders(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique,user_id uuid not null references public.profiles(id),market_id uuid not null references public.markets(id),
 side text not null check(side in ('yes','no')),action text not null check(action in ('buy','sell')),price numeric not null check(price>=.0001 and price<=.9999 and price=round(price,4)),
 quantity numeric not null check(quantity>=.0001 and quantity<=1000000 and quantity=round(quantity,4)),filled numeric not null default 0 check(filled>=0 and filled<=quantity),
 remaining numeric generated always as (quantity-filled) stored,
 status text not null default 'open' check(status in ('open','filled','cancelled','expired')),tif text not null check(tif in ('GTC','GTD','FOK','FAK')),
 expires_at timestamptz not null,requested_expiry timestamptz,created_at timestamptz not null default clock_timestamp(),sequence bigint generated always as identity unique
);
create index orders_book_idx on public.orders(market_id,status,side,action,price,sequence);
create index orders_member_idx on public.orders(user_id,status,created_at desc);
create index orders_expiry_idx on public.orders(expires_at) where status='open';
create table public.order_fills(id uuid primary key default gen_random_uuid(),market_id uuid not null references public.markets(id),maker_order_id uuid not null references public.orders(id),taker_order_id uuid not null references public.orders(id),kind text not null check(kind in ('direct','mint','merge')),quantity numeric not null check(quantity>0),yes_price numeric not null check(yes_price>0 and yes_price<1),created_at timestamptz not null default clock_timestamp(),sequence bigint generated always as identity unique);
create index order_fills_market_idx on public.order_fills(market_id,sequence);
create index order_fills_maker_idx on public.order_fills(maker_order_id);
create index order_fills_taker_idx on public.order_fills(taker_order_id);
create table public.order_events(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),user_id uuid not null references public.profiles(id),event text not null,details jsonb not null default '{}',created_at timestamptz not null default clock_timestamp());
create index order_events_order_idx on public.order_events(order_id,created_at);
create index order_events_user_idx on public.order_events(user_id);
alter table public.trades add column order_id uuid references public.orders(id);
alter table public.trades add column fill_id uuid references public.order_fills(id);
create index trades_order_idx on public.trades(order_id);
create index trades_fill_idx on public.trades(fill_id);
alter table public.orders enable row level security;
alter table public.order_fills enable row level security;
alter table public.order_events enable row level security;
create policy own_orders on public.orders for select to authenticated using(user_id=(select auth.uid()) and (select private.is_member()));
create policy member_fills on public.order_fills for select to authenticated using((select private.is_member()) and exists(select 1 from public.markets m where m.id=market_id));
create policy own_order_events on public.order_events for select to authenticated using(user_id=(select auth.uid()) and (select private.is_member()));
revoke all on public.orders,public.order_fills,public.order_events from public,anon,authenticated;
grant select on public.orders,public.order_fills,public.order_events to authenticated;
create trigger immutable_fills before update or delete on public.order_fills for each row execute function private.immutable_record();
create trigger immutable_order_events before update or delete on public.order_events for each row execute function private.immutable_record();
alter publication supabase_realtime add table public.orders,public.order_fills;

create or replace function private.market_created() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into private.credit_accounts values('market:'||new.id,0);
 if new.execution_model='amm' then perform private.transfer('treasury','market:'||new.id,private.cost(0,0,new.liquidity),'Market reserve',new.id);end if;
 return new;
end $$;
-- Legacy AMM buys also respect cash reserved in other markets.
do $$declare d text;
begin
 d:=pg_get_functiondef('private.trade_v1(uuid,text,text,numeric,numeric,uuid)'::regprocedure);
 d:=replace(d,'total>w.balance','total>(w.balance-w.reserved_balance)');execute d;
 d:=pg_get_functiondef('private.trade(uuid,text,text,numeric,numeric,uuid)'::regprocedure);
 d:=replace(d,'perform pg_advisory_xact_lock(84271001);','perform pg_advisory_xact_lock(84271001); if exists(select 1 from public.markets where id=p_market and execution_model=''clob'') then raise exception ''This market uses an order book. Refresh the app to place an order.'';end if;');execute d;
end $$;

create function private.book_levels(p_market uuid,p_side text,p_action text,p_exclude uuid default null) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('price',price,'size',size) order by case when p_action='buy' then price else -price end),'[]'::jsonb) from (
  select effective.price,sum(effective.remaining) size from (
   select case when o.side=p_side then o.price else 1-o.price end price,o.remaining
   from public.orders o join public.profiles p on p.id=o.user_id
   where o.market_id=p_market and o.status='open' and o.remaining>0 and o.expires_at>clock_timestamp() and p.active and (p.frozen_until is null or p.frozen_until<=clock_timestamp()) and (p_exclude is null or o.user_id<>p_exclude)
   and ((o.side=p_side and o.action<>p_action) or (o.side<>p_side and o.action=p_action))
  ) effective group by effective.price
 ) levels
$$;
create function private.refresh_book(p_market uuid) returns void language plpgsql security definer set search_path='' as $$
declare bid numeric;ask numeric;last_price numeric;display_price numeric;
begin
 select last_trade_price into last_price from public.markets where id=p_market;
 bid:=(private.book_levels(p_market,'yes','sell')->0->>'price')::numeric;
 ask:=(private.book_levels(p_market,'yes','buy')->0->>'price')::numeric;
 display_price:=case when bid is not null and ask is not null and ask>=bid and ask-bid<=.1 then (bid+ask)/2 else last_price end;
 update public.markets set probability=coalesce(display_price,probability),price_available=display_price is not null,book_version=book_version+1 where id=p_market and execution_model='clob' and status<>'resolved';
end $$;
create function private.close_order(p_order uuid,p_status text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
 select * into o from public.orders where id=p_order for update;
 if not found or o.status<>'open' then return false;end if;
 if o.action='buy' then update public.wallets set reserved_balance=reserved_balance-o.price*o.remaining where user_id=o.user_id;
 else update public.positions set reserved_shares=reserved_shares-o.remaining where user_id=o.user_id and market_id=o.market_id and side=o.side;end if;
 update public.orders set status=p_status where id=o.id;
 insert into public.order_events(order_id,user_id,event,details) values(o.id,o.user_id,p_status,jsonb_build_object('reason',p_reason,'unfilled',o.remaining));return true;
end $$;
create function private.expire_orders(p_market uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare o record;touched uuid[]:='{}';mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 for o in select orders.id,orders.market_id,orders.expires_at,m.closes_at from public.orders orders join public.markets m on m.id=orders.market_id join public.profiles p on p.id=orders.user_id
 where orders.status='open' and (p_market is null or orders.market_id=p_market) and (orders.expires_at<=clock_timestamp() or m.closes_at<=clock_timestamp() or m.status<>'open' or m.paused or m.archived or not p.active or p.frozen_until>clock_timestamp()) order by orders.sequence loop
  perform private.close_order(o.id,case when o.expires_at<=clock_timestamp() or o.closes_at<=clock_timestamp() then 'expired' else 'cancelled' end,'Market closed, order expired or account unavailable');
  if not o.market_id=any(touched) then touched:=array_append(touched,o.market_id);end if;
 end loop;
 foreach mid in array touched loop perform private.refresh_book(mid);end loop;
end $$;
-- Clear orders on market changes without recursively updating that same market row.
create function private.market_order_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
declare o record;
begin
 if old.execution_model='clob' and ((new.status<>'open' and new.status is distinct from old.status) or (new.paused and not old.paused) or (new.archived and not old.archived) or new.closes_at is distinct from old.closes_at) then
  perform pg_advisory_xact_lock(84271001);
  for o in select id from public.orders where market_id=old.id and status='open' order by sequence loop perform private.close_order(o.id,'cancelled','Market state or deadline changed');end loop;
  new.book_version:=old.book_version+1;
 end if;return new;
end $$;
create trigger market_order_cleanup before update of status,paused,archived,closes_at on public.markets for each row execute function private.market_order_cleanup();
create function private.member_order_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
declare o record;touched uuid[]:='{}';mid uuid;
begin
 if (not new.active and old.active) or (new.frozen_until>clock_timestamp() and new.frozen_until is distinct from old.frozen_until) then
  perform pg_advisory_xact_lock(84271001);
  for o in select id,market_id from public.orders where user_id=new.id and status='open' order by sequence loop perform private.close_order(o.id,'cancelled','Account removed or timed out');if not o.market_id=any(touched) then touched:=array_append(touched,o.market_id);end if;end loop;
  foreach mid in array touched loop perform private.refresh_book(mid);end loop;
 end if;return new;
end $$;
create trigger member_order_cleanup after update of active,frozen_until on public.profiles for each row execute function private.member_order_cleanup();

-- Apply one side of a matched execution. Buy legs run before sell legs.
create function private.fill_leg(p_order uuid,p_quantity numeric,p_price numeric,p_yes numeric,p_fill uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders;amount numeric:=p_quantity*p_price;
begin
 select * into o from public.orders where id=p_order for update;
 if o.status<>'open' or o.remaining<p_quantity then raise exception 'Order is no longer available';end if;
 if o.action='buy' then
  update public.wallets set reserved_balance=reserved_balance-o.price*p_quantity,balance=balance-amount where user_id=o.user_id;
  insert into public.positions(user_id,market_id,side,shares,net_cost) values(o.user_id,o.market_id,o.side,p_quantity,amount) on conflict(user_id,market_id,side) do update set shares=public.positions.shares+excluded.shares,net_cost=public.positions.net_cost+excluded.net_cost;
 else
  update public.positions set reserved_shares=reserved_shares-p_quantity,shares=shares-p_quantity,net_cost=net_cost-amount where user_id=o.user_id and market_id=o.market_id and side=o.side;
  update public.wallets set balance=balance+amount where user_id=o.user_id;
 end if;
 insert into public.ledger(user_id,market_id,amount,reason) values(o.user_id,o.market_id,case when o.action='buy' then -amount else amount end,o.action||' '||o.side);
 insert into public.trades(request_id,user_id,market_id,side,action,shares,total,probability,order_id,fill_id) values(gen_random_uuid(),o.user_id,o.market_id,o.side,o.action,p_quantity,amount,p_yes,o.id,p_fill);
 update public.orders set filled=filled+p_quantity,status=case when filled+p_quantity=quantity then 'filled' else 'open' end where id=o.id;
 insert into public.order_events(order_id,user_id,event,details) values(o.id,o.user_id,'fill',jsonb_build_object('fill_id',p_fill,'quantity',p_quantity,'price',p_price));
end $$;
create function private.place_order(p_market uuid,p_side text,p_action text,p_price numeric,p_quantity numeric,p_tif text,p_expires timestamptz,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;o public.orders;maker public.orders;effective numeric;qty numeric;yes_price numeric;fid uuid;kind text;existing public.orders;expiry timestamptz;attempts integer:=0;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null then raise exception 'A request ID is required';end if;
 select * into existing from public.orders where request_id=p_request;
 if found then
  if existing.user_id<>uid or existing.market_id<>p_market or existing.side is distinct from p_side or existing.action is distinct from p_action or existing.price is distinct from p_price or existing.quantity is distinct from p_quantity or existing.tif is distinct from p_tif or existing.requested_expiry is distinct from p_expires then raise exception 'Request ID already used for a different order';end if;
  return to_jsonb(existing);
 end if;
 if p_side is null or p_side not in ('yes','no') or p_action is null or p_action not in ('buy','sell') or p_tif is null or p_tif not in ('GTC','GTD','FOK','FAK') then raise exception 'Invalid order type';end if;
 if p_price is null or p_price::text in ('NaN','Infinity','-Infinity') or p_price<.0001 or p_price>.9999 or p_price<>round(p_price,4) then raise exception 'Price must be between 0.0001 and 0.9999, with up to 4 decimal places';end if;
 if p_quantity is null or p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity<.0001 or p_quantity>1000000 or p_quantity<>round(p_quantity,4) then raise exception 'Enter 0.0001 to 1,000,000 shares, with up to 4 decimal places';end if;
 perform private.expire_orders(null);
 select * into m from public.markets where id=p_market for update;
 if not found or m.execution_model<>'clob' then raise exception 'Choose an order-book market';end if;
 if m.status<>'open' or m.paused or m.archived or m.history_deleted_at is not null or m.closes_at<=clock_timestamp() then raise exception 'Trading is closed';end if;
 if p_tif='GTD' and (p_expires is null or p_expires<=clock_timestamp() or p_expires>m.closes_at) then raise exception 'Choose an order expiry before the market closes';end if;
 if p_tif<>'GTD' and p_expires is not null then raise exception 'Only GTD orders accept a custom expiry';end if;
 expiry:=case when p_tif='GTD' then p_expires else m.closes_at end;
 if (select count(*) from public.orders where user_id=uid and status='open')>=100 then raise exception 'Cancel an open order before placing more';end if;
 if p_action='buy' then
  update public.wallets set reserved_balance=reserved_balance+p_price*p_quantity where user_id=uid and balance-reserved_balance>=p_price*p_quantity;
  if not found then raise exception 'Insufficient available credits for this order';end if;
 else
  update public.positions set reserved_shares=reserved_shares+p_quantity where user_id=uid and market_id=p_market and side=p_side and shares-reserved_shares>=p_quantity;
  if not found then raise exception 'Insufficient available shares to sell';end if;
 end if;
 insert into public.orders(request_id,user_id,market_id,side,action,price,quantity,tif,expires_at,requested_expiry) values(p_request,uid,p_market,p_side,p_action,p_price,p_quantity,p_tif,expiry,p_expires) returning * into o;
 insert into public.order_events(order_id,user_id,event,details) values(o.id,uid,'placed',jsonb_build_object('side',p_side,'action',p_action,'price',p_price,'quantity',p_quantity,'tif',p_tif));
 loop
  select * into o from public.orders where id=o.id;
  exit when o.remaining=0;
  select candidate.* into maker from public.orders candidate join public.profiles p on p.id=candidate.user_id
   where candidate.market_id=p_market and candidate.id<>o.id and candidate.status='open' and candidate.remaining>0 and candidate.expires_at>clock_timestamp() and p.active and (p.frozen_until is null or p.frozen_until<=clock_timestamp())
   and ((candidate.side=p_side and candidate.action<>p_action) or (candidate.side<>p_side and candidate.action=p_action))
   and case when p_action='buy' then (case when candidate.side=p_side then candidate.price else 1-candidate.price end)<=p_price else (case when candidate.side=p_side then candidate.price else 1-candidate.price end)>=p_price end
   order by case when p_action='buy' then (case when candidate.side=p_side then candidate.price else 1-candidate.price end) else -(case when candidate.side=p_side then candidate.price else 1-candidate.price end) end,candidate.sequence limit 1 for update of candidate;
  exit when not found;
  attempts:=attempts+1;if attempts>1000 then raise exception 'Too many matches; use a smaller order';end if;
  if maker.user_id=uid then perform private.close_order(maker.id,'cancelled','Self-trade prevention');continue;end if;
  effective:=case when maker.side=p_side then maker.price else 1-maker.price end;
  qty:=least(o.remaining,maker.remaining);yes_price:=case when p_side='yes' then effective else 1-effective end;
  kind:=case when maker.side=p_side then 'direct' when p_action='buy' then 'mint' else 'merge' end;
  insert into public.order_fills(market_id,maker_order_id,taker_order_id,kind,quantity,yes_price) values(p_market,maker.id,o.id,kind,qty,yes_price) returning id into fid;
  if p_action='buy' then
   perform private.fill_leg(o.id,qty,effective,yes_price,fid);
   perform private.fill_leg(maker.id,qty,maker.price,yes_price,fid);
  elsif maker.action='buy' then
   perform private.fill_leg(maker.id,qty,maker.price,yes_price,fid);
   perform private.fill_leg(o.id,qty,effective,yes_price,fid);
  else
   perform private.fill_leg(o.id,qty,effective,yes_price,fid);
   perform private.fill_leg(maker.id,qty,maker.price,yes_price,fid);
  end if;
  update public.markets set q_yes=q_yes+case kind when 'mint' then qty when 'merge' then -qty else 0 end,q_no=q_no+case kind when 'mint' then qty when 'merge' then -qty else 0 end,volume=volume+case when kind='direct' then qty*effective else qty end,last_trade_price=yes_price where id=p_market;
 end loop;
 select * into o from public.orders where id=o.id;
 if p_tif='FOK' and o.remaining>0 then raise exception 'Not enough matching orders to fill everything. No trade was made.';end if;
 if p_tif='FAK' and o.remaining>0 then perform private.close_order(o.id,'cancelled','Unfilled immediate-order remainder');end if;
 perform private.refresh_book(p_market);
 select * into o from public.orders where id=o.id;return to_jsonb(o);
end $$;
create function private.cancel_order(p_order uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();o public.orders;
begin
 perform pg_advisory_xact_lock(84271001);select * into o from public.orders where id=p_order for update;
 if not found or o.user_id<>uid then raise exception 'Choose one of your own orders';end if;
 if private.close_order(o.id,'cancelled','Cancelled by owner') then perform private.refresh_book(o.market_id);end if;
end $$;
create function private.cancel_my_orders(p_market uuid default null) returns integer language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();o record;count_cancelled integer:=0;
begin
 perform pg_advisory_xact_lock(84271001);
 for o in select id from public.orders where user_id=uid and status='open' and (p_market is null or market_id=p_market) order by sequence loop perform private.cancel_order(o.id);count_cancelled:=count_cancelled+1;end loop;
 return count_cancelled;
end $$;
create function private.sync_orders() returns void language plpgsql security definer set search_path='' as $$begin perform private.require_member();perform private.expire_orders(null);end $$;
create function private.get_my_orders(p_market uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();
begin
 perform private.expire_orders(null);
 return coalesce((select jsonb_agg(to_jsonb(o) order by case when o.status='open' then 0 else 1 end,o.sequence desc) from (select * from public.orders where user_id=uid and (p_market is null or market_id=p_market) order by case when status='open' then 0 else 1 end,sequence desc limit 200) o),'[]'::jsonb);
end $$;
create function private.orderbook(p_market uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();m public.markets;
begin
 perform private.expire_orders(p_market);select * into m from public.markets where id=p_market;
 if not found or m.execution_model<>'clob' or (m.history_deleted_at is not null and not private.is_admin()) then raise exception 'Order book unavailable';end if;
 return jsonb_build_object('bids',jsonb_build_object('yes',private.book_levels(p_market,'yes','sell'),'no',private.book_levels(p_market,'no','sell')),'asks',jsonb_build_object('yes',private.book_levels(p_market,'yes','buy'),'no',private.book_levels(p_market,'no','buy')),
 'executable_bids',jsonb_build_object('yes',private.book_levels(p_market,'yes','sell',uid),'no',private.book_levels(p_market,'no','sell',uid)),'executable_asks',jsonb_build_object('yes',private.book_levels(p_market,'yes','buy',uid),'no',private.book_levels(p_market,'no','buy',uid)),
 'orders',private.get_my_orders(p_market),'price_available',m.price_available,'price',m.probability);
end $$;

-- Final-state invariants: no duplicate collateral, double-pledged cash or naked sells.
create function private.check_orderbook() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.wallets w where w.reserved_balance<>(select coalesce(sum(o.price*o.remaining),0) from public.orders o where o.user_id=w.user_id and o.status='open' and o.action='buy')) then raise exception 'Cash reservations do not reconcile';end if;
 if exists(select 1 from public.positions p where p.reserved_shares<>(select coalesce(sum(o.remaining),0) from public.orders o where o.user_id=p.user_id and o.market_id=p.market_id and o.side=p.side and o.status='open' and o.action='sell')) then raise exception 'Share reservations do not reconcile';end if;
 if exists(select 1 from public.markets m join private.credit_accounts a on a.id='market:'||m.id where m.execution_model='clob' and (m.q_yes<>m.q_no or m.q_yes<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='yes') or m.q_no<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='no') or a.balance<>case when m.status='resolved' then 0 else m.q_yes end)) then raise exception 'Order-book shares and collateral do not reconcile';end if;
 return null;
end $$;
create constraint trigger check_orders after insert or update or delete on public.orders deferrable initially deferred for each row execute function private.check_orderbook();
create constraint trigger check_order_wallets after insert or update on public.wallets deferrable initially deferred for each row execute function private.check_orderbook();
create constraint trigger check_order_positions after insert or update on public.positions deferrable initially deferred for each row execute function private.check_orderbook();
create constraint trigger check_order_markets after insert or update on public.markets deferrable initially deferred for each row execute function private.check_orderbook();
create constraint trigger check_order_accounts after insert or update on private.credit_accounts deferrable initially deferred for each row execute function private.check_orderbook();

create function private.create_market_v5(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 if nullif(trim(p_title),'') is null or nullif(trim(p_yes),'') is null or nullif(trim(p_no),'') is null then raise exception 'Question and Yes/No meanings are required';end if;
 if p_verifications is null or p_verifications<2 then raise exception 'At least two confirmations are required';end if;
 if p_closes is null or p_closes<=clock_timestamp() or p_closes>now()+interval '1 year' then raise exception 'Choose a future closing time within one year';end if;
 if (select count(*) from public.markets where creator_id=uid and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached';end if;
 insert into public.markets(creator_id,title,description,category,emoji,closes_at,liquidity,yes_rule,no_rule,required_verifications,execution_model,price_available,counter_enabled,counter_label) values(uid,trim(p_title),'Yes: '||trim(p_yes)||E'\nNo: '||trim(p_no),'Other','',p_closes,400,trim(p_yes),trim(p_no),p_verifications,'clob',false,coalesce(p_counter,false),coalesce(nullif(trim(p_counter_label),''),'Count')) returning id into mid;
 return mid;
end $$;
create function public.create_market_v5(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v5(p_title,p_yes,p_no,p_closes,p_verifications,p_counter,p_counter_label)$$;
create or replace function public.create_market_v4(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer,p_counter boolean,p_counter_label text) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v5(p_title,p_yes,p_no,p_closes,p_verifications,p_counter,p_counter_label)$$;
create or replace function public.create_market_v3(p_title text,p_yes text,p_no text,p_closes timestamptz,p_liquidity numeric,p_verifications integer) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v5(p_title,p_yes,p_no,p_closes,p_verifications,false,'Count')$$;
create or replace function public.create_market_v2(p_title text,p_description text,p_category text,p_closes timestamptz,p_liquidity numeric) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v5(p_title,p_description,'The event does not happen as described.',p_closes,2,false,'Count')$$;
create or replace function public.create_market(p_title text,p_description text,p_category text,p_emoji text,p_closes timestamptz) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v5(p_title,p_description,'The event does not happen as described.',p_closes,2,false,'Count')$$;
create function public.place_order(p_market uuid,p_side text,p_action text,p_price numeric,p_quantity numeric,p_tif text,p_expires timestamptz,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.place_order(p_market,p_side,p_action,p_price,p_quantity,p_tif,p_expires,p_request)$$;
create function public.cancel_order(p_order uuid) returns void language sql security invoker set search_path='' as $$select private.cancel_order(p_order)$$;
create function public.cancel_my_orders(p_market uuid default null) returns integer language sql security invoker set search_path='' as $$select private.cancel_my_orders(p_market)$$;
create function public.get_my_orders(p_market uuid default null) returns jsonb language sql security invoker set search_path='' as $$select private.get_my_orders(p_market)$$;
create function public.orderbook(p_market uuid) returns jsonb language sql security invoker set search_path='' as $$select private.orderbook(p_market)$$;
create function public.sync_orders() returns void language sql security invoker set search_path='' as $$select private.sync_orders()$$;
revoke all on function private.book_levels(uuid,text,text,uuid),private.refresh_book(uuid),private.close_order(uuid,text,text),private.expire_orders(uuid),private.market_order_cleanup(),private.member_order_cleanup(),private.fill_leg(uuid,numeric,numeric,numeric,uuid),private.check_orderbook() from public,anon,authenticated;
revoke all on function private.place_order(uuid,text,text,numeric,numeric,text,timestamptz,uuid),private.cancel_order(uuid),private.cancel_my_orders(uuid),private.get_my_orders(uuid),private.orderbook(uuid),private.sync_orders(),private.create_market_v5(text,text,text,timestamptz,integer,boolean,text),public.place_order(uuid,text,text,numeric,numeric,text,timestamptz,uuid),public.cancel_order(uuid),public.cancel_my_orders(uuid),public.get_my_orders(uuid),public.orderbook(uuid),public.sync_orders(),public.create_market_v5(text,text,text,timestamptz,integer,boolean,text) from public,anon,authenticated;
grant execute on function private.place_order(uuid,text,text,numeric,numeric,text,timestamptz,uuid),private.cancel_order(uuid),private.cancel_my_orders(uuid),private.get_my_orders(uuid),private.orderbook(uuid),private.sync_orders(),private.create_market_v5(text,text,text,timestamptz,integer,boolean,text),public.place_order(uuid,text,text,numeric,numeric,text,timestamptz,uuid),public.cancel_order(uuid),public.cancel_my_orders(uuid),public.get_my_orders(uuid),public.orderbook(uuid),public.sync_orders(),public.create_market_v5(text,text,text,timestamptz,integer,boolean,text) to authenticated;
-- Administrative cash displays distinguish available and reserved money.
do $$declare d text;
begin
 d:=pg_get_functiondef('private.admin_members()'::regprocedure);d:=replace(d,'''balance'',w.balance,','''balance'',w.balance-w.reserved_balance,''reserved_balance'',w.reserved_balance,');execute d;
end $$;
create or replace function private.release_market_reserve() returns trigger language plpgsql security definer set search_path='' as $$
declare remaining numeric;
begin
 if new.status='resolved' and old.status<>'resolved' then
  select balance into remaining from private.credit_accounts where id='market:'||new.id;
  if new.execution_model='clob' then
   if remaining<>0 then raise exception 'Order-book collateral was not fully paid to holders';end if;
  else perform private.transfer('market:'||new.id,'treasury',remaining,'Unused reserve',new.id);end if;
 end if;return new;
end $$;
