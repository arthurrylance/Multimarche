-- Initial estimates are explicit, bounded, and shared by pricing and quotes.
alter table public.markets add column initial_probability numeric not null default .5 check(initial_probability between .01 and .99);
alter table public.wallets add column loan_collateral numeric not null default 0 check(loan_collateral>=0 and reserved_balance+loan_collateral<=balance);
alter table public.orders add column net_remaining numeric not null default 0 check(net_remaining>=0 and net_remaining<=remaining);
create table public.leverage_positions(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),market_id uuid not null references public.markets(id),factor integer not null check(factor in(5,10)),stake numeric not null check(stake>0),principal numeric not null check(principal>0),remaining numeric not null check(remaining>=0 and remaining<=principal),status text not null default 'active' check(status in('active','closed')),created_at timestamptz not null default now(),closed_at timestamptz);
create unique index one_active_leverage_per_user on public.leverage_positions(user_id) where status='active';
create index leverage_market_idx on public.leverage_positions(market_id);
alter table public.leverage_positions enable row level security;
create policy own_leverage on public.leverage_positions for select to authenticated using(user_id=(select auth.uid()) and (select private.is_member()));
revoke all on public.leverage_positions from public,anon,authenticated;grant select on public.leverage_positions to authenticated;
alter publication supabase_realtime add table public.leverage_positions;
create table private.prediction_requests(request_id uuid primary key,user_id uuid not null references public.profiles(id),spec jsonb not null,result jsonb not null,created_at timestamptz not null default now());
alter table private.prediction_requests enable row level security;
revoke all on private.prediction_requests from public,anon,authenticated;

create function private.amm_cost(m public.markets,y numeric,n numeric) returns numeric language sql immutable set search_path='' as $$select case when m.initial_probability=.5 then private.cost(y,n,m.liquidity) else private.cost(y+m.liquidity*ln(m.initial_probability),n+m.liquidity*ln(1-m.initial_probability),m.liquidity) end$$;
create function private.amm_probability(m public.markets,y numeric,n numeric) returns numeric language sql immutable set search_path='' as $$select 1/(1+exp(greatest(-700,least(700,(n-y)/m.liquidity+ln((1-m.initial_probability)/m.initial_probability)))))$$;
create or replace function private.market_created() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into private.credit_accounts values('market:'||new.id,0);if new.execution_model='amm' then perform private.transfer('treasury','market:'||new.id,case when new.initial_probability=.5 then private.cost(0,0,new.liquidity) else -new.liquidity*ln(least(new.initial_probability,1-new.initial_probability))+.000001 end,'Market reserve',new.id);end if;return new;end $$;
-- Keep the established exact AMM transaction core, replacing only its pricing and free-cash guard.
do $$declare d text;
begin
 d:=pg_get_functiondef('private.trade_v1(uuid,text,text,numeric,numeric,uuid)'::regprocedure);
 d:=replace(d,'private.cost(ny,nn,m.liquidity)-private.cost(m.q_yes,m.q_no,m.liquidity)','private.amm_cost(m,ny,nn)-private.amm_cost(m,m.q_yes,m.q_no)');
 d:=replace(d,'(w.balance-w.reserved_balance)','(w.balance-w.reserved_balance-w.loan_collateral)');
 d:=replace(d,'(1/(1+exp(greatest(-700,least(700,(nn-ny)/m.liquidity)))))::double precision','private.amm_probability(m,ny,nn)::double precision');execute d;
end $$;

create function private.settle_finished_loans(p_market uuid default null,p_user uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare loan public.leverage_positions;
begin
 for loan in select l.* from public.leverage_positions l join public.markets m on m.id=l.market_id where l.status='active' and (p_market is null or l.market_id=p_market) and (p_user is null or l.user_id=p_user) and (m.status='resolved' or (not exists(select 1 from public.positions p where p.user_id=l.user_id and p.market_id=l.market_id and p.shares>0) and not exists(select 1 from public.orders o where o.user_id=l.user_id and o.market_id=l.market_id and o.status='open'))) order by l.id for update of l loop
  update public.wallets set balance=balance-loan.remaining,loan_collateral=loan_collateral-loan.remaining where user_id=loan.user_id;
  insert into public.ledger(user_id,amount,reason) values(loan.user_id,-loan.remaining,'Leverage repayment');
  update public.leverage_positions set remaining=0,status='closed',closed_at=clock_timestamp() where id=loan.id;
 end loop;
end $$;
create function private.market_loan_settlement() returns trigger language plpgsql security definer set search_path='' as $$begin if new.status='resolved' then perform private.settle_finished_loans(new.id,null);end if;return new;end $$;
create trigger market_loan_settlement after update of status on public.markets for each row execute function private.market_loan_settlement();

-- A buy towards the opposite end closes old exposure before opening the new end.
create or replace function private.trade(p_market uuid,p_side text,p_action text,p_shares numeric,p_limit numeric,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;prior private.prediction_requests;spec jsonb;opposite text;held numeric;closing numeric;proceeds numeric:=0;spent numeric:=0;result jsonb;
begin
 perform pg_advisory_xact_lock(84271001);spec:=jsonb_build_object('kind','amm_trade','market',p_market,'side',p_side,'action',p_action,'shares',p_shares,'limit',p_limit);
 select * into prior from private.prediction_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 if p_side is null or p_side not in('yes','no') or p_action is null or p_action not in('buy','sell') or p_shares is null or p_shares::text in('NaN','Infinity','-Infinity') or p_shares<.0001 or p_shares>10000 or p_limit is null or p_limit::text in('NaN','Infinity','-Infinity') or p_limit<0 or p_request is null then raise exception 'Invalid trade';end if;
 select * into m from public.markets where id=p_market for update;
 if not found or m.execution_model<>'amm' or m.status<>'open' or m.paused or m.archived or m.closes_at<=clock_timestamp() then raise exception 'Trading is closed';end if;
 opposite:=case p_side when 'yes' then 'no' else 'yes' end;
 select coalesce(sum(shares),0) into held from public.positions where user_id=uid and market_id=p_market and side=opposite;
 if p_action='buy' and held>0 then
  closing:=least(held,p_shares);
  result:=private.trade_v1(p_market,opposite,'sell',closing,0,p_request);proceeds:=(result->>'total')::numeric;
  if p_shares>closing then result:=private.trade_v1(p_market,p_side,'buy',p_shares-closing,p_limit,gen_random_uuid());spent:=(result->>'total')::numeric;end if;
  if closing-proceeds+spent>p_limit then raise exception 'Price changed; review your prediction';end if;
  result:=jsonb_build_object('total',closing-proceeds+spent,'shares',p_shares,'cash_change',proceeds-spent,'reduced',closing);
 else result:=private.trade_v1(p_market,p_side,p_action,p_shares,p_limit,p_request);end if;
 insert into private.prediction_requests values(p_request,uid,spec,result,now());
 perform private.settle_finished_loans(p_market,uid);return result;
end $$;

-- Netting order collateral: opposite holdings fund reductions and subsequent crossing through zero.
create or replace function private.close_order(p_order uuid,p_status text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare o public.orders;opposite text;
begin
 select * into o from public.orders where id=p_order for update;if not found or o.status<>'open' then return false;end if;
 opposite:=case o.side when 'yes' then 'no' else 'yes' end;
 if o.action='buy' then
  update public.wallets set reserved_balance=reserved_balance-greatest(0,o.price*o.remaining-o.net_remaining) where user_id=o.user_id;
  if o.net_remaining>0 then update public.positions set reserved_shares=reserved_shares-o.net_remaining where user_id=o.user_id and market_id=o.market_id and side=opposite;end if;
 else update public.positions set reserved_shares=reserved_shares-o.remaining where user_id=o.user_id and market_id=o.market_id and side=o.side;end if;
 update public.orders set status=p_status,net_remaining=0 where id=o.id;
 insert into public.order_events(order_id,user_id,event,details) values(o.id,o.user_id,p_status,jsonb_build_object('reason',p_reason,'unfilled',o.remaining));return true;
end $$;
create or replace function private.fill_leg(p_order uuid,p_quantity numeric,p_price numeric,p_yes numeric,p_fill uuid) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders;real_action text;real_side text;real_price numeric;net_used numeric;old_hold numeric;new_hold numeric;amount numeric;
begin
 select * into o from public.orders where id=p_order for update;
 if o.status<>'open' or o.remaining<p_quantity then raise exception 'Order is no longer available';end if;
 net_used:=case when o.action='buy' then least(o.net_remaining,p_quantity) else 0 end;
 if net_used>0 and net_used<>p_quantity then raise exception 'Netting fill must stop at zero';end if;
 real_action:=case when net_used>0 then 'sell' else o.action end;real_side:=case when net_used>0 then case o.side when 'yes' then 'no' else 'yes' end else o.side end;real_price:=case when net_used>0 then 1-p_price else p_price end;amount:=p_quantity*real_price;
 old_hold:=case when o.action='buy' then greatest(0,o.price*o.remaining-o.net_remaining) else 0 end;
 new_hold:=case when o.action='buy' then greatest(0,o.price*(o.remaining-p_quantity)-(o.net_remaining-net_used)) else 0 end;
 if real_action='buy' then
  update public.wallets set reserved_balance=reserved_balance-old_hold+new_hold,balance=balance-amount where user_id=o.user_id;
  insert into public.positions(user_id,market_id,side,shares,net_cost) values(o.user_id,o.market_id,real_side,p_quantity,amount) on conflict(user_id,market_id,side) do update set shares=public.positions.shares+excluded.shares,net_cost=public.positions.net_cost+excluded.net_cost;
 else
  update public.positions set reserved_shares=reserved_shares-p_quantity,shares=shares-p_quantity,net_cost=net_cost-amount where user_id=o.user_id and market_id=o.market_id and side=real_side;
  update public.wallets set reserved_balance=reserved_balance-old_hold+new_hold,balance=balance+amount where user_id=o.user_id;
 end if;
 insert into public.ledger(user_id,market_id,amount,reason) values(o.user_id,o.market_id,case when real_action='buy' then -amount else amount end,case when net_used>0 then 'Reduce ' else '' end||real_action||' '||real_side);
 insert into public.trades(request_id,user_id,market_id,side,action,shares,total,probability,order_id,fill_id) values(gen_random_uuid(),o.user_id,o.market_id,real_side,real_action,p_quantity,amount,p_yes,o.id,p_fill);
 update public.orders set filled=filled+p_quantity,net_remaining=net_remaining-net_used,status=case when filled+p_quantity=quantity then 'filled' else 'open' end where id=o.id;
 insert into public.order_events(order_id,user_id,event,details) values(o.id,o.user_id,'fill',jsonb_build_object('fill_id',p_fill,'quantity',p_quantity,'price',p_price,'actual_action',real_action,'actual_side',real_side));
end $$;

create or replace function private.place_order(p_market uuid,p_side text,p_action text,p_price numeric,p_quantity numeric,p_tif text,p_expires timestamptz,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;o public.orders;maker public.orders;effective numeric;qty numeric;yes_price numeric;fid uuid;kind text;existing public.orders;expiry timestamptz;attempts integer:=0;net_qty numeric:=0;cash_hold numeric;leg_action text;maker_action text;maker_net numeric;
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
  for existing in select * from public.orders where user_id=uid and market_id=p_market and status='open' order by sequence loop perform private.close_order(existing.id,'cancelled','Replaced direction');end loop;
  select least(p_quantity,coalesce(sum(shares-reserved_shares),0)) into net_qty from public.positions where user_id=uid and market_id=p_market and side=case p_side when 'yes' then 'no' else 'yes' end;
  cash_hold:=greatest(0,p_price*p_quantity-net_qty);
  if net_qty>0 then update public.positions set reserved_shares=reserved_shares+net_qty where user_id=uid and market_id=p_market and side=case p_side when 'yes' then 'no' else 'yes' end;end if;
  update public.wallets set reserved_balance=reserved_balance+cash_hold where user_id=uid and balance-reserved_balance-loan_collateral>=cash_hold;
  if not found then raise exception 'Insufficient available credits for this order';end if;
 else
  update public.positions set reserved_shares=reserved_shares+p_quantity where user_id=uid and market_id=p_market and side=p_side and shares-reserved_shares>=p_quantity;
  if not found then raise exception 'Insufficient available shares to sell';end if;
 end if;
 insert into public.orders(request_id,user_id,market_id,side,action,price,quantity,tif,expires_at,requested_expiry,net_remaining) values(p_request,uid,p_market,p_side,p_action,p_price,p_quantity,p_tif,expiry,p_expires,net_qty) returning * into o;
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
  -- Existing resting buys keep their original cash hold until they next match.
  if maker.action='buy' and maker.net_remaining=0 and exists(select 1 from public.positions where user_id=maker.user_id and market_id=p_market and side<>maker.side and shares>0) then
   select least(maker.remaining,coalesce(sum(shares-reserved_shares),0)) into maker_net from public.positions where user_id=maker.user_id and market_id=p_market and side<>maker.side;
   if maker_net=0 then perform private.close_order(maker.id,'cancelled','Opposite position already reserved');continue;end if;
   update public.wallets set reserved_balance=reserved_balance-maker.price*maker.remaining+greatest(0,maker.price*maker.remaining-maker_net) where user_id=maker.user_id;
   update public.positions set reserved_shares=reserved_shares+maker_net where user_id=maker.user_id and market_id=p_market and side<>maker.side;
   update public.orders set net_remaining=maker_net where id=maker.id returning * into maker;
  end if;
  effective:=case when maker.side=p_side then maker.price else 1-maker.price end;
  qty:=least(o.remaining,maker.remaining,case when o.net_remaining>0 then o.net_remaining else o.remaining end,case when maker.net_remaining>0 then maker.net_remaining else maker.remaining end);yes_price:=case when p_side='yes' then effective else 1-effective end;
  leg_action:=case when o.net_remaining>0 then 'sell' else o.action end;maker_action:=case when maker.net_remaining>0 then 'sell' else maker.action end;
  kind:=case when leg_action<>maker_action then 'direct' when leg_action='buy' then 'mint' else 'merge' end;
  insert into public.order_fills(market_id,maker_order_id,taker_order_id,kind,quantity,yes_price) values(p_market,maker.id,o.id,kind,qty,yes_price) returning id into fid;
  if leg_action='buy' then
   perform private.fill_leg(o.id,qty,effective,yes_price,fid);
   perform private.fill_leg(maker.id,qty,maker.price,yes_price,fid);
  elsif maker_action='buy' then
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
 perform private.settle_finished_loans(p_market,null);
 select * into o from public.orders where id=o.id;return to_jsonb(o);
end $$;
create or replace function private.check_orderbook() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.wallets w where w.reserved_balance<>(select coalesce(sum(greatest(0,o.price*o.remaining-o.net_remaining)),0) from public.orders o where o.user_id=w.user_id and o.status='open' and o.action='buy')) then raise exception 'Cash reservations do not reconcile';end if;
 if exists(select 1 from public.positions p where p.reserved_shares<>(select coalesce(sum(case when o.action='sell' then o.remaining else o.net_remaining end),0) from public.orders o where o.user_id=p.user_id and o.market_id=p.market_id and o.status='open' and ((o.action='sell' and o.side=p.side) or (o.action='buy' and o.side<>p.side)))) then raise exception 'Share reservations do not reconcile';end if;
 if exists(select 1 from public.markets m join private.credit_accounts a on a.id='market:'||m.id where m.execution_model='clob' and (m.q_yes<>m.q_no or m.q_yes<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='yes') or m.q_no<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='no') or a.balance<>case when m.status='resolved' then 0 else m.q_yes end)) then raise exception 'Order-book shares and collateral do not reconcile';end if;
 if exists(select 1 from public.positions a join public.positions b on a.user_id=b.user_id and a.market_id=b.market_id and a.side<>b.side join public.markets m on m.id=a.market_id where m.status<>'resolved' and a.shares>0 and b.shares>0) then raise exception 'Only one direction may be held per market';end if;
 if exists(select 1 from public.wallets w where w.loan_collateral<>(select coalesce(sum(l.remaining),0) from public.leverage_positions l where l.user_id=w.user_id and l.status='active')) then raise exception 'Loan collateral does not reconcile';end if;
 return null;
end $$;

do $$declare d text;sig text;
begin
 foreach sig in array array['private.cancel_order(uuid)','private.get_my_orders(uuid)','private.sync_orders()'] loop
  d:=pg_get_functiondef(sig::regprocedure);
  if sig='private.cancel_order(uuid)' then d:=replace(d,'end if;','end if; perform private.settle_finished_loans(o.market_id,uid);');
  else d:=replace(d,'perform private.expire_orders(null);','perform private.expire_orders(null);perform private.settle_finished_loans(null,null);');end if;execute d;
 end loop;
end $$;
CREATE OR REPLACE FUNCTION private.admin_members()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform private.require_admin();return coalesce((select jsonb_agg(jsonb_build_object(
 'id',p.id,'username',p.username,'nickname',p.nickname,'active',p.active,'deleted_at',p.deleted_at,'auth_deleted_at',p.auth_deleted_at,'frozen_until',p.frozen_until,'created_at',p.created_at,'balance',w.balance-w.reserved_balance-w.loan_collateral,'reserved_balance',w.reserved_balance,
 'admin',exists(select 1 from private.admins a where a.user_id=p.id),
 'equity',w.balance-w.loan_collateral+coalesce((select sum(pos.shares*case when pos.side='yes' then m.probability else 1-m.probability end) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and m.status<>'resolved'),0),
 'open_bets',(select count(distinct pos.market_id) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and pos.shares>0 and m.status<>'resolved'),
 'spent',(select coalesce(sum(total),0) from public.trades where user_id=p.id and action='buy'),
 'sales',(select coalesce(sum(total),0) from public.trades where user_id=p.id and action='sell'),
 'payouts',(select coalesce(sum(amount),0) from public.ledger where user_id=p.id and reason like 'Settlement:%')
 ) order by p.username) from public.profiles p join public.wallets w on w.user_id=p.id),'[]'::jsonb);end $function$
;
CREATE OR REPLACE FUNCTION private.leaderboard()
 RETURNS TABLE(id uuid, username text, equity numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.require_member();
 return query select p.id,p.username,w.balance-w.loan_collateral+coalesce((select sum(pos.shares*case when pos.side='yes' then m.probability else 1-m.probability end) from public.positions pos join public.markets m on m.id=pos.market_id where pos.user_id=p.id and m.status<>'resolved'),0)::numeric from public.profiles p join public.wallets w on w.user_id=p.id where p.active order by 3 desc;
end $function$
;
CREATE OR REPLACE FUNCTION private.create_market_group_v2(p_title text, p_options jsonb, p_closes timestamp with time zone, p_verifications integer, p_counter boolean, p_counter_label text, p_execution text, p_request uuid, p_probability numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=private.require_player();g public.market_groups;spec text;item jsonb;label text;yr text;nr text;mid uuid;ids jsonb:='[]';position integer:=0;remaining integer;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null then raise exception 'A request ID is required';end if;
 spec:=encode(extensions.digest(jsonb_build_object('title',p_title,'options',p_options,'closes',p_closes,'verifications',p_verifications,'counter',p_counter,'counter_label',p_counter_label,'execution',p_execution,'probability',p_probability)::text,'sha256'),'hex');
 select * into g from public.market_groups where request_id=p_request;
 if found then
  if g.creator_id<>uid or g.creation_hash<>spec then raise exception 'Request ID already used for a different group';end if;
  select coalesce(jsonb_agg(id order by group_position),'[]'::jsonb) into ids from public.markets where group_id=g.id;
  return jsonb_build_object('group_id',g.id,'market_ids',ids);
 end if;
 if p_title is null or p_title !~ '[^[:space:]]' then raise exception 'A group question is required';end if;
 if p_options is null or jsonb_typeof(p_options)<>'array' then raise exception 'Add 2 to 10 options';end if;
 if jsonb_array_length(p_options)<2 or jsonb_array_length(p_options)>10 then raise exception 'Add 2 to 10 options';end if;
 for item in select value from jsonb_array_elements(p_options) loop
  if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'label') is distinct from 'string' or (item->>'label') !~ '[^[:space:]]' then raise exception 'Each option needs a label';end if;
  if (item ? 'yes' and jsonb_typeof(item->'yes') not in ('string','null')) or (item ? 'no' and jsonb_typeof(item->'no') not in ('string','null')) then raise exception 'Option meanings must be text';end if;
 end loop;
 if (select count(distinct lower(btrim(value->>'label'))) from jsonb_array_elements(p_options))<>jsonb_array_length(p_options) then raise exception 'Use a different label for each option';end if;
 select greatest(0,10-count(*)) into remaining from public.markets where creator_id=uid and economy_round=(select reset_version from private.economy where id=1) and created_at>now()-interval '1 day';
 if jsonb_array_length(p_options)>remaining then raise exception 'You can create % more options today; each option counts toward the daily market limit',remaining;end if;
 insert into public.market_groups(creator_id,title,request_id,creation_hash) values(uid,btrim(p_title),p_request,spec) returning * into g;
 for item in select value from jsonb_array_elements(p_options) loop
  label:=btrim(item->>'label');yr:=coalesce(nullif(btrim(item->>'yes'),''),'“'||label||'” happens during this event.');nr:=coalesce(nullif(btrim(item->>'no'),''),'“'||label||'” does not happen during this event.');
  mid:=private.create_market_v7(g.title||' · '||label,yr,nr,p_closes,p_verifications,p_counter,p_counter_label,p_execution,coalesce((item->>'probability')::numeric,p_probability));
  update public.markets set group_id=g.id,option_label=label,group_position=position where id=mid;
  ids:=ids||jsonb_build_array(mid);position:=position+1;
 end loop;
 return jsonb_build_object('group_id',g.id,'market_ids',ids);
end $function$
;

create function private.create_market_v7(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text,p_probability numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();mid uuid;
begin
 perform pg_advisory_xact_lock(84271001);
 if nullif(trim(p_title),'') is null or nullif(trim(p_yes),'') is null or nullif(trim(p_no),'') is null then raise exception 'Question and Yes/No meanings are required';end if;
 if p_execution is null or p_execution not in('amm','clob') then raise exception 'Choose Automatic or Order book';end if;
 if p_probability is null or p_probability::text in('NaN','Infinity','-Infinity') or p_probability not between .01 and .99 then raise exception 'Starting likelihood must be 1–99 percent';end if;
 if p_verifications is null or p_verifications<2 then raise exception 'At least two confirmations are required';end if;
 if p_closes is null or p_closes<=clock_timestamp() or p_closes>now()+interval '1 year' then raise exception 'Choose a future closing time within one year';end if;
 if (select count(*) from public.markets where creator_id=uid and economy_round=(select reset_version from private.economy where id=1) and created_at>now()-interval '1 day')>=10 then raise exception 'Daily market limit reached';end if;
 insert into public.markets(creator_id,title,description,category,emoji,closes_at,liquidity,yes_rule,no_rule,required_verifications,execution_model,price_available,counter_enabled,counter_label,initial_probability,probability) values(uid,trim(p_title),'Yes: '||trim(p_yes)||E'\nNo: '||trim(p_no),'Other','',p_closes,400,trim(p_yes),trim(p_no),p_verifications,p_execution,p_execution='amm',coalesce(p_counter,false),coalesce(nullif(trim(p_counter_label),''),'Count'),p_probability,p_probability) returning id into mid;
 return mid;
end $$;
create function public.create_market_v7(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text,p_probability numeric) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v7(p_title,p_yes,p_no,p_closes,p_verifications,p_counter,p_counter_label,p_execution,p_probability)$$;
create function public.create_market_group_v2(p_title text,p_options jsonb,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text,p_request uuid,p_probability numeric) returns jsonb language sql security invoker set search_path='' as $$select private.create_market_group_v2(p_title,p_options,p_closes,p_verifications,p_counter,p_counter_label,p_execution,p_request,p_probability)$$;

create function private.predict(p_market uuid,p_side text,p_budget numeric,p_factor integer,p_price numeric,p_tif text,p_expires timestamptz,p_min_shares numeric,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;w public.wallets;prior private.prediction_requests;spec jsonb;result jsonb;qty numeric;lo numeric:=0;hi numeric:=10000;mid numeric;notional numeric;borrowed numeric;loan_id uuid;i integer;child_request uuid:=gen_random_uuid();o record;
begin
 perform pg_advisory_xact_lock(84271001);
 spec:=jsonb_build_object('kind','prediction','market',p_market,'side',p_side,'budget',p_budget,'factor',p_factor,'price',p_price,'tif',p_tif,'expires',p_expires,'min_shares',p_min_shares);
 select * into prior from private.prediction_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 if p_request is null or p_side is null or p_side not in('yes','no') or p_factor is null or p_factor not in(1,5,10) or p_budget is null or p_budget::text in('NaN','Infinity','-Infinity') or p_budget<=0 or p_budget>1000000 or p_min_shares is null or p_min_shares::text in('NaN','Infinity','-Infinity') or p_min_shares<0 then raise exception 'Invalid prediction';end if;
 perform private.expire_orders(null);perform private.settle_finished_loans(null,uid);
 select * into m from public.markets where id=p_market for update;
 if not found or m.status<>'open' or m.paused or m.archived or m.history_deleted_at is not null or m.closes_at<=clock_timestamp() then raise exception 'Betting is closed';end if;
 notional:=p_budget*p_factor;
 if p_factor>1 then
  if exists(select 1 from public.leverage_positions where user_id=uid and status='active') then raise exception 'Finish your current leveraged market first';end if;
  if exists(select 1 from public.positions where user_id=uid and market_id=p_market and shares>0) then raise exception 'Leverage must start from a flat position';end if;
  for o in select id from public.orders where user_id=uid and market_id=p_market and status='open' order by sequence loop perform private.close_order(o.id,'cancelled','New leveraged prediction');end loop;
  select * into w from public.wallets where user_id=uid for update;
  if w.balance-w.reserved_balance-w.loan_collateral<notional then raise exception 'Keep the full maximum loss available: % credits',notional;end if;
  borrowed:=p_budget*(p_factor-1);
  update public.wallets set balance=balance+borrowed,loan_collateral=loan_collateral+borrowed where user_id=uid;
  insert into public.leverage_positions(user_id,market_id,factor,stake,principal,remaining) values(uid,p_market,p_factor,p_budget,borrowed,borrowed) returning id into loan_id;
  insert into public.ledger(user_id,amount,reason) values(uid,borrowed,'Leverage borrowing');
 end if;
 if m.execution_model='amm' then
  for i in 1..64 loop mid:=(lo+hi)/2;if private.amm_cost(m,m.q_yes+case p_side when 'yes' then mid else 0 end,m.q_no+case p_side when 'no' then mid else 0 end)-private.amm_cost(m,m.q_yes,m.q_no)>notional then hi:=mid;else lo:=mid;end if;end loop;
  qty:=floor(lo*10000)/10000;
  if qty<.0001 or qty<p_min_shares then raise exception 'Price changed; review your prediction';end if;
  result:=private.trade(p_market,p_side,'buy',qty,notional,child_request);
 else
  if p_price is null or p_price::text in('NaN','Infinity','-Infinity') or p_price not between .0001 and .9999 or p_price<>round(p_price,4) then raise exception 'Choose a valid limit price';end if;
  qty:=floor(notional/p_price*10000)/10000;
  if qty>1000000 or qty<.0001 then raise exception 'Choose a smaller prediction';end if;
  result:=private.place_order(p_market,p_side,'buy',p_price,qty,p_tif,p_expires,child_request);
 end if;
 perform private.settle_finished_loans(p_market,null);
 result:=result||jsonb_build_object('factor',p_factor,'loan_id',loan_id);
 insert into private.prediction_requests values(p_request,uid,spec,result,now());return result;
end $$;
create function public.predict(p_market uuid,p_side text,p_budget numeric,p_factor integer,p_price numeric,p_tif text,p_expires timestamptz,p_min_shares numeric,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.predict(p_market,p_side,p_budget,p_factor,p_price,p_tif,p_expires,p_min_shares,p_request)$$;

-- Preserve existing orders and holdings. Refuse installation if manual reconciliation is needed.
do $$begin
 if exists(select 1 from public.positions a join public.positions b on a.user_id=b.user_id and a.market_id=b.market_id and a.side='yes' and b.side='no' join public.markets m on m.id=a.market_id where a.shares>0 and b.shares>0 and m.status<>'resolved') then raise exception 'Existing mixed positions require reconciliation before this upgrade';end if;
end $$;

-- All helpers are closed; only validated member endpoints are callable.
revoke all on function private.amm_cost(public.markets,numeric,numeric),private.amm_probability(public.markets,numeric,numeric),private.settle_finished_loans(uuid,uuid),private.market_loan_settlement() from public,anon,authenticated;
revoke all on function private.predict(uuid,text,numeric,integer,numeric,text,timestamptz,numeric,uuid),public.predict(uuid,text,numeric,integer,numeric,text,timestamptz,numeric,uuid),private.create_market_v7(text,text,text,timestamptz,integer,boolean,text,text,numeric),public.create_market_v7(text,text,text,timestamptz,integer,boolean,text,text,numeric),private.create_market_group_v2(text,jsonb,timestamptz,integer,boolean,text,text,uuid,numeric),public.create_market_group_v2(text,jsonb,timestamptz,integer,boolean,text,text,uuid,numeric) from public,anon,authenticated;
grant execute on function private.predict(uuid,text,numeric,integer,numeric,text,timestamptz,numeric,uuid),public.predict(uuid,text,numeric,integer,numeric,text,timestamptz,numeric,uuid),private.create_market_v7(text,text,text,timestamptz,integer,boolean,text,text,numeric),public.create_market_v7(text,text,text,timestamptz,integer,boolean,text,text,numeric),private.create_market_group_v2(text,jsonb,timestamptz,integer,boolean,text,text,uuid,numeric),public.create_market_group_v2(text,jsonb,timestamptz,integer,boolean,text,text,uuid,numeric) to authenticated;
