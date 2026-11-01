-- Virtual credit loans require the stake only. Only a recorded loan repayment may overdraw a user.
-- No balances, orders or existing loan records are changed by this migration.
alter table public.wallets drop constraint wallets_balance_check;
alter table public.wallets drop constraint wallets_check;
alter table public.wallets drop constraint wallets_check1;
alter table public.wallets add constraint wallet_reservations_funded check(reserved_balance>=0 and reserved_balance<=greatest(balance,0));
alter table public.wallets add constraint wallet_debt_nonnegative check(loan_collateral>=0);
comment on column public.wallets.loan_collateral is 'Legacy field name: outstanding borrowed principal, no longer collateral or a cash reservation.';
alter table public.wallets add column borrowed_balance numeric generated always as (loan_collateral) stored;
alter table private.credit_accounts drop constraint credit_accounts_balance_check;
alter table private.credit_accounts add constraint funded_system_accounts check(balance>=0 or id like 'user:%');

create or replace function private.transfer(p_from text,p_to text,p_amount numeric,p_reason text,p_market uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare repayment boolean;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_amount=0 then return;end if;
 if p_amount is null or p_amount::text in('NaN','Infinity','-Infinity') or p_amount<0 or p_from=p_to then raise exception 'Invalid transfer';end if;
 repayment:=p_reason='Leverage repayment' and p_to='treasury' and exists(select 1 from public.leverage_positions l where 'user:'||l.user_id=p_from and l.status='active' and l.remaining>=p_amount);
 update private.credit_accounts set balance=balance-p_amount where id=p_from and (balance>=p_amount or repayment);
 if not found then raise exception 'Insufficient funded reserves';end if;
 update private.credit_accounts set balance=balance+p_amount where id=p_to;
 if not found then raise exception 'Unknown destination';end if;
 perform private.audit_append(jsonb_build_object('kind','transfer','from',private.account_key(p_from),'to',private.account_key(p_to),'amount',p_amount::text,'reason',case when p_reason like 'Admin allocation:%' then 'Admin allocation' else p_reason end,'market',case when p_market is not null then private.account_key(p_market::text) end));
end $$;

-- Reserved orders cannot prevent a debt settlement; release them before repayment if necessary.
create or replace function private.settle_finished_loans(p_market uuid default null,p_user uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare loan public.leverage_positions;o record;
begin
 for loan in select l.* from public.leverage_positions l join public.markets m on m.id=l.market_id where l.status='active' and (p_market is null or l.market_id=p_market) and (p_user is null or l.user_id=p_user) and (m.status='resolved' or (not exists(select 1 from public.positions p where p.user_id=l.user_id and p.market_id=l.market_id and p.shares>0) and not exists(select 1 from public.orders ord where ord.user_id=l.user_id and ord.market_id=l.market_id and ord.status='open'))) order by l.id for update of l loop
  if exists(select 1 from public.wallets w where w.user_id=loan.user_id and w.balance-loan.remaining<w.reserved_balance) then
   for o in select id,market_id from public.orders where user_id=loan.user_id and status='open' and action='buy' order by sequence loop
    perform private.close_order(o.id,'cancelled','Credits needed for loan repayment');perform private.refresh_book(o.market_id);
   end loop;
  end if;
  update public.wallets set balance=balance-loan.remaining,loan_collateral=loan_collateral-loan.remaining where user_id=loan.user_id;
  insert into public.ledger(user_id,amount,reason) values(loan.user_id,-loan.remaining,'Leverage repayment');
  update public.leverage_positions set remaining=0,status='closed',closed_at=clock_timestamp() where id=loan.id;
 end loop;
end $$;

do $$declare d text;changed text;
begin
 d:=pg_get_functiondef('private.predict(uuid,text,numeric,integer,numeric,text,timestamptz,numeric,uuid)'::regprocedure);
 changed:=replace(d,$text$if w.balance-w.reserved_balance-w.loan_collateral<notional then raise exception 'Keep the full maximum loss available: % credits',notional;end if;$text$,$text$if w.balance-w.reserved_balance<p_budget then raise exception 'Insufficient available credits for your stake';end if;$text$);
 if d=changed then raise exception 'Prediction stake guard not found';end if;execute changed;
 d:=pg_get_functiondef('private.trade_v1(uuid,text,text,numeric,numeric,uuid)'::regprocedure);
 changed:=replace(d,'(w.balance-w.reserved_balance-w.loan_collateral)','(w.balance-w.reserved_balance)');
 if d=changed then raise exception 'AMM cash guard not found';end if;execute changed;
 d:=pg_get_functiondef('private.place_order(uuid,text,text,numeric,numeric,text,timestamptz,uuid)'::regprocedure);
 changed:=replace(d,'and balance-reserved_balance-loan_collateral>=cash_hold','and (cash_hold=0 or balance-reserved_balance>=cash_hold)');
 if d=changed then raise exception 'Order cash guard not found';end if;
 changed:=replace(changed,'cash_hold:=greatest(0,p_price*p_quantity-net_qty);',E'cash_hold:=greatest(0,p_price*p_quantity-net_qty);\n  if p_quantity>net_qty and exists(select 1 from public.wallets where user_id=uid and balance<0) then raise exception ''Clear your negative balance before adding to a bet'';end if;');execute changed;
 d:=pg_get_functiondef('private.admin_members()'::regprocedure);
 d:=replace(d,$text$'balance',w.balance-w.reserved_balance-w.loan_collateral,$text$,$text$'balance',w.balance-w.reserved_balance,'borrowed_balance',w.loan_collateral,$text$);execute d;
 -- Collect positive balances before clearing negative accounts during an explicit future reset.
 d:=pg_get_functiondef('private.admin_reset_economy(text,text,uuid)'::regprocedure);
 d:=replace(d,'from public.wallets order by user_id loop','from public.wallets order by balance desc,user_id loop');execute d;
end $$;
