-- Own-account cancellation uses the established accounting core. No live orders are changed here.
create function private.cancel_prediction(p_market uuid,p_close boolean,p_min_return numeric,p_price numeric,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();prior private.prediction_requests;spec jsonb;m public.markets;p record;result jsonb;orders jsonb:='[]';cancelled integer;total numeric:=0;remaining numeric;chunk numeric;i integer:=0;
begin
 perform pg_advisory_xact_lock(84271001);
 spec:=jsonb_build_object('kind','cancel_prediction','market',p_market,'close',p_close,'min_return',p_min_return,'price',p_price);
 select * into prior from private.prediction_requests where request_id=p_request;
 if found then if prior.user_id<>uid or prior.spec<>spec then raise exception 'Request ID already used';end if;return prior.result;end if;
 if p_request is null or p_close is null or p_min_return is null or p_min_return::text in('NaN','Infinity','-Infinity') or p_min_return<0 then raise exception 'Invalid cancellation';end if;
 select * into m from public.markets where id=p_market for update;
 if not found then raise exception 'Market unavailable';end if;
 cancelled:=private.cancel_my_orders(p_market);
 if p_close and exists(select 1 from public.positions where user_id=uid and market_id=p_market and shares>0) then
  perform private.require_player();
  if m.status<>'open' or m.paused or m.archived or m.history_deleted_at is not null or m.closes_at<=clock_timestamp() then raise exception 'This bet can no longer be closed';end if;
  if m.execution_model='clob' and (p_price is null or p_price::text in('NaN','Infinity','-Infinity') or p_price not between .0001 and .9999 or p_price<>round(p_price,4)) then raise exception 'Choose a valid closing price';end if;
  for p in select side,shares from public.positions where user_id=uid and market_id=p_market and shares>0 order by side loop
   remaining:=p.shares;
   while remaining>0 loop
    i:=i+1;if i>1000 then raise exception 'Position too large to close at once';end if;
    chunk:=least(remaining,case when m.execution_model='amm' then 10000 else 1000000 end);
    if m.execution_model='amm' then result:=private.trade(p_market,p.side,'sell',chunk,0,gen_random_uuid());total:=total+(result->>'total')::numeric;
    else result:=private.place_order(p_market,p.side,'sell',p_price,chunk,'GTC',null,gen_random_uuid());orders:=orders||jsonb_build_array(result);end if;
    remaining:=remaining-chunk;
   end loop;
  end loop;
  if m.execution_model='amm' and total<p_min_return then raise exception 'Price changed; review the cancellation';end if;
 end if;
 perform private.settle_finished_loans(p_market,uid);
 result:=jsonb_build_object('cancelled',cancelled,'returned',total,'orders',orders);
 insert into private.prediction_requests values(p_request,uid,spec,result,now());return result;
end $$;
create function public.cancel_prediction(p_market uuid,p_close boolean,p_min_return numeric,p_price numeric,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.cancel_prediction(p_market,p_close,p_min_return,p_price,p_request)$$;
revoke all on function private.cancel_prediction(uuid,boolean,numeric,numeric,uuid),public.cancel_prediction(uuid,boolean,numeric,numeric,uuid) from public,anon,authenticated;
grant execute on function private.cancel_prediction(uuid,boolean,numeric,numeric,uuid),public.cancel_prediction(uuid,boolean,numeric,numeric,uuid) to authenticated;
