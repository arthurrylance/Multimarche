create function private.admin_remove_credits(p_user uuid, p_amount numeric, p_reason text, p_request uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := private.require_admin();
  reason text := btrim(p_reason);
  previous public.admin_events;
begin
  if p_amount is null or p_amount < 0.01 or p_amount > 100000
     or p_amount <> round(p_amount, 2) or coalesce(length(reason), 0) < 5
     or p_request is null then
    raise exception 'Invalid credit removal';
  end if;

  perform pg_advisory_xact_lock(84271001);
  select * into previous from public.admin_events where id = p_request;
  if found then
    if previous.actor_id = actor and previous.action = 'credit_removal'
       and previous.target_id = p_user::text and previous.reason = reason
       and previous.details->'amount' = to_jsonb(p_amount) then
      return;
    end if;
    raise exception 'Request ID already used';
  end if;

  if not exists (select 1 from public.profiles where id = p_user and active) then
    raise exception 'Unknown active member';
  end if;

  update public.wallets
  set balance = balance - p_amount
  where user_id = p_user and balance - reserved_balance >= p_amount;
  if not found then
    raise exception 'Insufficient available credits';
  end if;

  -- The ledger trigger returns the credits to treasury and records the audited transfer.
  insert into public.ledger(user_id, amount, reason)
  values (p_user, -p_amount, 'Admin credit removal');

  insert into public.admin_events(id, actor_id, action, target_id, reason, details)
  values (p_request, actor, 'credit_removal', p_user::text, reason, jsonb_build_object('amount', p_amount));
end;
$$;

create function public.admin_remove_credits(p_user uuid, p_amount numeric, p_reason text, p_request uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.admin_remove_credits(p_user, p_amount, p_reason, p_request);
$$;

revoke all on function private.admin_remove_credits(uuid, numeric, text, uuid),
  public.admin_remove_credits(uuid, numeric, text, uuid) from public, anon;
grant execute on function private.admin_remove_credits(uuid, numeric, text, uuid),
  public.admin_remove_credits(uuid, numeric, text, uuid) to authenticated;
