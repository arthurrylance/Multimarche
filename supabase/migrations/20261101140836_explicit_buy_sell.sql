-- Preserve funded resting orders and existing holdings; release only legacy netting orders.
select pg_advisory_xact_lock(84271001);
do $$declare o record;begin
 for o in select id,market_id from public.orders where status='open' and net_remaining>0 order by sequence loop
  perform private.close_order(o.id,'cancelled','Automatic direction changes removed; place an explicit buy or sell');
  perform private.refresh_book(o.market_id);
 end loop;
end $$;
CREATE OR REPLACE FUNCTION private.trade(p_market uuid, p_side text, p_action text, p_shares numeric, p_limit numeric, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=private.require_player();m public.markets;prior private.prediction_requests;spec jsonb;opposite text;held numeric;closing numeric;proceeds numeric:=0;spent numeric:=0;result jsonb;
begin
 perform pg_advisory_xact_lock(84271001);spec:=jsonb_build_object('kind','amm_trade','market',p_market,'side',p_side,'action',p_action,'shares',p_shares,'limit',p_limit);
 select * into prior from private.prediction_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 if p_side is null or p_side not in('yes','no') or p_action is null or p_action not in('buy','sell') or p_shares is null or p_shares::text in('NaN','Infinity','-Infinity') or p_shares<.0001 or p_shares>10000 or p_limit is null or p_limit::text in('NaN','Infinity','-Infinity') or p_limit<0 or p_request is null then raise exception 'Invalid trade';end if;
 select * into m from public.markets where id=p_market for update;
 if not found or m.execution_model<>'amm' or m.status<>'open' or m.paused or m.archived or m.history_deleted_at is not null or m.closes_at<=clock_timestamp() then raise exception 'Trading is closed';end if;
 result:=private.trade_v1(p_market,p_side,p_action,p_shares,p_limit,p_request);
 insert into private.prediction_requests values(p_request,uid,spec,result,now());
 perform private.settle_finished_loans(p_market,uid);return result;
end $function$
;
create or replace function private.place_order(p_market uuid,p_side text,p_action text,p_price numeric,p_quantity numeric,p_tif text,p_expires timestamptz,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 perform private.settle_finished_loans(p_market,null);
 select * into o from public.orders where id=o.id;return to_jsonb(o);
end $$;
CREATE OR REPLACE FUNCTION private.check_orderbook()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if exists(select 1 from public.wallets w where w.reserved_balance<>(select coalesce(sum(greatest(0,o.price*o.remaining-o.net_remaining)),0) from public.orders o where o.user_id=w.user_id and o.status='open' and o.action='buy')) then raise exception 'Cash reservations do not reconcile';end if;
 if exists(select 1 from public.positions p where p.reserved_shares<>(select coalesce(sum(case when o.action='sell' then o.remaining else o.net_remaining end),0) from public.orders o where o.user_id=p.user_id and o.market_id=p.market_id and o.status='open' and ((o.action='sell' and o.side=p.side) or (o.action='buy' and o.side<>p.side)))) then raise exception 'Share reservations do not reconcile';end if;
 if exists(select 1 from public.markets m join private.credit_accounts a on a.id='market:'||m.id where m.execution_model='clob' and (m.q_yes<>m.q_no or m.q_yes<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='yes') or m.q_no<>(select coalesce(sum(shares),0) from public.positions where market_id=m.id and side='no') or a.balance<>case when m.status='resolved' then 0 else m.q_yes end)) then raise exception 'Order-book shares and collateral do not reconcile';end if;
 if exists(select 1 from public.wallets w where w.loan_collateral<>(select coalesce(sum(l.remaining),0) from public.leverage_positions l where l.user_id=w.user_id and l.status='active')) then raise exception 'Loan collateral does not reconcile';end if;
 return null;
end $function$;

-- New explicit endpoint: a buy spends credits; a sell specifies owned shares.
create function private.execute_trade(p_market uuid,p_side text,p_action text,p_amount numeric,p_factor integer,p_price numeric,p_tif text,p_expires timestamptz,p_min_return numeric,p_min_shares numeric,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;prior private.prediction_requests;spec jsonb;result jsonb;child uuid:=gen_random_uuid();
begin
 perform pg_advisory_xact_lock(84271001);
 spec:=jsonb_build_object('kind','explicit_trade','market',p_market,'side',p_side,'action',p_action,'amount',p_amount,'factor',p_factor,'price',p_price,'tif',p_tif,'expires',p_expires,'min_return',p_min_return,'min_shares',p_min_shares);
 select * into prior from private.prediction_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 if p_request is null or p_side is null or p_side not in('yes','no') or p_action is null or p_action not in('buy','sell') or p_amount is null or p_amount::text in('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount>1000000 or p_factor is null or p_factor not in(1,5,10) or p_min_return is null or p_min_return::text in('NaN','Infinity','-Infinity') or p_min_return<0 or p_min_shares is null or p_min_shares::text in('NaN','Infinity','-Infinity') or p_min_shares<0 then raise exception 'Invalid trade';end if;
 if p_action='sell' and p_factor<>1 then raise exception 'Selling does not use leverage';end if;
 select * into m from public.markets where id=p_market for update;
 if not found or m.status<>'open' or m.paused or m.archived or m.history_deleted_at is not null or m.closes_at<=clock_timestamp() then raise exception 'Trading is closed';end if;
 if p_action='buy' then result:=private.predict(p_market,p_side,p_amount,p_factor,p_price,p_tif,p_expires,p_min_shares,child);
 elsif m.execution_model='amm' then result:=private.trade(p_market,p_side,'sell',p_amount,p_min_return,child);
 else result:=private.place_order(p_market,p_side,'sell',p_price,p_amount,p_tif,p_expires,child);end if;
 perform private.settle_finished_loans(p_market,uid);
 insert into private.prediction_requests values(p_request,uid,spec,result,now());return result;
end $$;
create function public.execute_trade(p_market uuid,p_side text,p_action text,p_amount numeric,p_factor integer,p_price numeric,p_tif text,p_expires timestamptz,p_min_return numeric,p_min_shares numeric,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.execute_trade(p_market,p_side,p_action,p_amount,p_factor,p_price,p_tif,p_expires,p_min_return,p_min_shares,p_request)$$;
revoke all on function private.execute_trade(uuid,text,text,numeric,integer,numeric,text,timestamptz,numeric,numeric,uuid),public.execute_trade(uuid,text,text,numeric,integer,numeric,text,timestamptz,numeric,numeric,uuid) from public,anon,authenticated;
grant execute on function private.execute_trade(uuid,text,text,numeric,integer,numeric,text,timestamptz,numeric,numeric,uuid),public.execute_trade(uuid,text,text,numeric,integer,numeric,text,timestamptz,numeric,numeric,uuid) to authenticated;
-- Stale tabs must refresh instead of submitting old automatic-netting previews.
create or replace function public.predict(p_market uuid,p_side text,p_budget numeric,p_factor integer,p_price numeric,p_tif text,p_expires timestamptz,p_min_shares numeric,p_request uuid) returns jsonb language plpgsql security invoker set search_path='' as $$begin raise exception 'Trading controls changed. Refresh the page to buy or sell.';end $$;
create or replace function public.cancel_prediction(p_market uuid,p_close boolean,p_min_return numeric,p_price numeric,p_request uuid) returns jsonb language plpgsql security invoker set search_path='' as $$begin raise exception 'Trading controls changed. Refresh the page and use Sell Yes or Sell No.';end $$;
