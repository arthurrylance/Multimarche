-- Own-account weighted acquisition cost; existing trading and settlement stay unchanged.
create function private.position_accounting(p_market uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.require_member();s text;t record;p public.positions;quantity numeric;basis numeric;released numeric;realised numeric:=0;spent numeric:=0;sales numeric:=0;result jsonb:='{}';
begin
 foreach s in array array['yes','no'] loop
  quantity:=0;basis:=0;
  for t in select action,shares,total from public.trades where user_id=uid and market_id=p_market and side=s order by sequence loop
   if t.action='buy' then quantity:=quantity+t.shares;basis:=basis+t.total;spent:=spent+t.total;
   else released:=case when quantity>0 then basis*least(t.shares,quantity)/quantity else 0 end;quantity:=greatest(0,quantity-t.shares);basis:=greatest(0,basis-released);realised:=realised+t.total-released;sales:=sales+t.total;end if;
  end loop;
  select * into p from public.positions where user_id=uid and market_id=p_market and side=s;
  if found then basis:=case when p.shares=0 then 0 when quantity>0 then basis*p.shares/quantity else greatest(0,p.net_cost) end;else basis:=0;end if;
  result:=result||jsonb_build_object(s,basis);
 end loop;
 return result||jsonb_build_object('spent',spent,'sales',sales,'realised_profit',realised);
end $$;
create function public.position_accounting(p_market uuid) returns jsonb language sql security invoker set search_path='' as $$select private.position_accounting(p_market)$$;
revoke all on function private.position_accounting(uuid),public.position_accounting(uuid) from public,anon,authenticated;
grant execute on function private.position_accounting(uuid),public.position_accounting(uuid) to authenticated;
