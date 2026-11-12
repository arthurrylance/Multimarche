-- Rollback-only fixtures for treasury credit removal and high-volume resolution.
begin;

insert into private.invites
values (encode(extensions.digest('admin-actions-fixture','sha256'),'hex'),3,now()+interval '1 hour');
insert into auth.users(id,email,raw_user_meta_data) values
  ('00000000-0000-4000-8000-000000002001','actions_admin@members.multimarche.invalid','{"username":"actions_admin","invite":"admin-actions-fixture"}'),
  ('00000000-0000-4000-8000-000000002002','actions_member@members.multimarche.invalid','{"username":"actions_member","invite":"admin-actions-fixture"}'),
  ('00000000-0000-4000-8000-000000002003','actions_voter@members.multimarche.invalid','{"username":"actions_voter","invite":"admin-actions-fixture"}');
insert into private.admins values ('00000000-0000-4000-8000-000000002001');

do $$
declare
  admin_id constant uuid := '00000000-0000-4000-8000-000000002001';
  member_id constant uuid := '00000000-0000-4000-8000-000000002002';
  voter_id constant uuid := '00000000-0000-4000-8000-000000002003';
  request_id uuid := gen_random_uuid();
  starting_balance numeric;
  before_state jsonb;
  after_state jsonb;
  high_market uuid;
  boundary_market uuid;
begin
  perform set_config('request.jwt.claim.sub', member_id::text, true);
  set local role authenticated;
  begin
    perform public.admin_remove_credits(member_id, 1, 'Unauthorized removal', gen_random_uuid());
    raise exception 'Member could remove credits';
  exception when raise_exception then
    if sqlerrm <> 'Admin access required' then raise; end if;
  end;
  reset role;

  select balance into strict starting_balance from public.wallets where user_id = member_id;
  update public.wallets set reserved_balance = starting_balance - 50 where user_id = member_id;
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  set local role authenticated;
  before_state := public.economy_status();
  begin
    perform public.admin_remove_credits(member_id, 51, 'Reserved credit test', gen_random_uuid());
    raise exception 'Reserved credits could be removed';
  exception when raise_exception then
    if sqlerrm <> 'Insufficient available credits' then raise; end if;
  end;

  perform public.admin_remove_credits(member_id, 25.50, 'Test private reason', request_id);
  perform public.admin_remove_credits(member_id, 25.5, 'Test private reason', request_id);
  after_state := public.economy_status();
  reset role;

  if (after_state->>'treasury')::numeric <> (before_state->>'treasury')::numeric + 25.50
     or after_state->>'total_supply' <> before_state->>'total_supply'
     or (select balance from public.wallets where user_id = member_id) <> starting_balance - 25.50
     or (select count(*) from public.ledger where user_id = member_id and reason = 'Admin credit removal' and amount = -25.50) <> 1
     or not exists (select 1 from public.admin_events where id = request_id and action = 'credit_removal' and reason = 'Test private reason')
     or exists (select 1 from public.audit_blocks where payload like '%Test private reason%')
     or not public.verify_audit() then
    raise exception 'Credit removal or audit totals are incorrect';
  end if;
  update public.wallets set reserved_balance = 0 where user_id = member_id;

  high_market := private.create_market_v2('High-volume resolution test', 'Test settlement with admin confirmation', 'Other', now()+interval '1 hour', 400);
  boundary_market := private.create_market_v2('Threshold resolution test', 'Test settlement at exactly 2000 credits', 'Other', now()+interval '1 hour', 400);
  perform public.trade(high_market, 'yes', 'buy', 10, 100, gen_random_uuid());
  update public.markets set volume = 2000.01 where id = high_market;
  update public.markets set volume = 2000 where id = boundary_market;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', member_id::text, true);
  perform public.resolve_market(high_market, 'yes', 'First vote');
  perform public.resolve_market(boundary_market, 'yes', 'First vote');
  perform set_config('request.jwt.claim.sub', voter_id::text, true);
  if public.resolve_market(high_market, 'yes', 'Second vote') <> 'proposed'
     or public.resolve_market(boundary_market, 'yes', 'Second vote') <> 'resolved' then
    raise exception 'The 2000-credit threshold was not enforced';
  end if;
  if (select status from public.markets where id = high_market) <> 'proposed'
     or (select outcome from public.markets where id = high_market) <> 'yes'
     or exists (select 1 from public.ledger where market_id = high_market and reason like 'Settlement:%') then
    raise exception 'A high-volume market paid out before admin confirmation';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform public.admin_market(high_market, 'settle', '{"outcome":"yes"}', 'Confirm voted outcome');
  if not exists (select 1 from public.markets where id = high_market and status = 'resolved' and admin_resolved)
     or (select count(*) from public.ledger where market_id = high_market and reason = 'Settlement: yes' and amount = 10) <> 1 then
    raise exception 'Admin confirmation did not resolve and pay out the market';
  end if;
end;
$$;
rollback;
