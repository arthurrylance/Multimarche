-- Keep free-form admin reasons off the public blockchain.
create or replace function private.transfer(p_from text,p_to text,p_amount numeric,p_reason text,p_market uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(84271001);
 if p_amount=0 then return;end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0 or p_from=p_to then raise exception 'Invalid transfer';end if;
 update private.credit_accounts set balance=balance-p_amount where id=p_from and balance>=p_amount;
 if not found then raise exception 'Insufficient funded reserves';end if;
 update private.credit_accounts set balance=balance+p_amount where id=p_to;
 if not found then raise exception 'Unknown destination';end if;
 perform private.audit_append(jsonb_build_object('kind','transfer','from',private.account_key(p_from),'to',private.account_key(p_to),'amount',p_amount::text,'reason',case when p_reason like 'Admin allocation:%' then 'Admin allocation' else p_reason end,'market',case when p_market is not null then private.account_key(p_market::text) end));
end $$;
