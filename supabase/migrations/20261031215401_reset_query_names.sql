-- Use unambiguous SQL aliases and counters in the reset/loss routines.
do $$declare d text;
begin
 d:=pg_get_functiondef('private.admin_reset_economy(text,text,uuid)'::regprocedure);
 d:=replace(replace(replace(d,'archived integer;','archived_count integer;'),'get diagnostics archived=row_count','get diagnostics archived_count=row_count'),'''archived_markets'',archived,','''archived_markets'',archived_count,');execute d;
 d:=pg_get_functiondef('private.loss_summary()'::regprocedure);
 d:=replace(d,'select distinct t.market_id,t.side from public.trades t join public.markets current_market on current_market.id=t.market_id where t.user_id=uid','select distinct trade_record.market_id,trade_record.side from public.trades trade_record join public.markets current_market on current_market.id=trade_record.market_id where trade_record.user_id=uid');execute d;
end $$;
