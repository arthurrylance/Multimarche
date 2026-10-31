-- Loss warnings use owned cash, excluding outstanding secured borrowing.
do $$declare d text;
begin
 d:=pg_get_functiondef('private.loss_summary()'::regprocedure);
 d:=replace(d,'select balance into cash from public.wallets','select balance-loan_collateral into cash from public.wallets');execute d;
end $$;
