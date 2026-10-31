-- Creation selects an execution model. Existing markets and positions are untouched.
create function private.create_market_v6(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform private.require_player();
 if p_execution='amm' then return private.create_market_v4(p_title,p_yes,p_no,p_closes,400,p_verifications,p_counter,p_counter_label);
 elsif p_execution='clob' then return private.create_market_v5(p_title,p_yes,p_no,p_closes,p_verifications,p_counter,p_counter_label);
 else raise exception 'Choose Automatic or Order book';end if;
end $$;
create function public.create_market_v6(p_title text,p_yes text,p_no text,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text) returns uuid language sql security invoker set search_path='' as $$select private.create_market_v6(p_title,p_yes,p_no,p_closes,p_verifications,p_counter,p_counter_label,p_execution)$$;
create function private.keep_execution_model() returns trigger language plpgsql set search_path='' as $$begin if new.execution_model is distinct from old.execution_model then raise exception 'A market pricing system cannot change after creation';end if;return new;end $$;
create trigger keep_execution_model before update of execution_model on public.markets for each row execute function private.keep_execution_model();

-- Conflicting observations pause settlement; each member can change or withdraw their own vote.
alter table public.markets add column resolution_disputed boolean not null default false;
create or replace function private.market_state_timestamp() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status<>'proposed' then new.resolution_disputed:=false;end if;
 if new.status is distinct from old.status or new.outcome is distinct from old.outcome or new.resolution_disputed is distinct from old.resolution_disputed then new.state_changed_at:=clock_timestamp();end if;
 return new;
end $$;
create function private.reconcile_resolution(p_market uuid) returns text language plpgsql security definer set search_path='' as $$
declare m public.markets;kinds integer;confirmations integer;winner text;pay record;
begin
 perform private.require_member();perform pg_advisory_xact_lock(84271001);
 select * into m from public.markets where id=p_market for update;
 if not found or m.status='resolved' then raise exception 'No unresolved market';end if;
 select count(distinct outcome),count(*),min(outcome) into kinds,confirmations,winner from public.resolution_votes where market_id=p_market;
 if kinds=0 then
  update public.markets set status='open',outcome=null,resolution_disputed=false,state_changed_at=clock_timestamp() where id=p_market;return 'open';
 elsif kinds>1 then
  update public.markets set status='proposed',outcome=null,resolution_disputed=true,state_changed_at=clock_timestamp() where id=p_market;return 'disputed';
 elsif confirmations<m.required_verifications then
  update public.markets set status='proposed',outcome=winner,resolution_disputed=false,state_changed_at=clock_timestamp() where id=p_market;return 'proposed';
 end if;
 for pay in select user_id,sum(shares*case when winner='void' then .5 when side=winner then 1 else 0 end) amount from public.positions where market_id=p_market group by user_id order by user_id loop
  update public.wallets set balance=balance+pay.amount where user_id=pay.user_id;
  insert into public.ledger(user_id,market_id,amount,reason) values(pay.user_id,p_market,pay.amount,'Settlement: '||winner);
 end loop;
 update public.markets set status='resolved',outcome=winner,resolved_at=now(),resolution_disputed=false,probability=case winner when 'yes' then 1 when 'no' then 0 else .5 end where id=p_market;return 'resolved';
end $$;
create or replace function private.resolve_market(p_market uuid,p_outcome text,p_evidence text) returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();m public.markets;previous text;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_outcome is null or p_outcome not in ('yes','no','void') then raise exception 'Invalid outcome';end if;
 select * into m from public.markets where id=p_market for update;
 if not found or m.history_deleted_at is not null then raise exception 'Market not found';end if;
 if m.status='resolved' then raise exception 'Already resolved';end if;
 select outcome into previous from public.resolution_votes where market_id=p_market and user_id=uid;
 if previous=p_outcome then raise exception 'You already voted %; change your vote or withdraw it',upper(p_outcome);end if;
 insert into public.resolution_votes(market_id,user_id,outcome,evidence) values(p_market,uid,p_outcome,coalesce(trim(p_evidence),'')) on conflict(market_id,user_id) do update set outcome=excluded.outcome,evidence=excluded.evidence,created_at=clock_timestamp();
 return private.reconcile_resolution(p_market);
end $$;
create or replace function private.withdraw_resolution(p_market uuid) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();
begin
 perform pg_advisory_xact_lock(84271001);
 if not exists(select 1 from public.markets where id=p_market and status='proposed') then raise exception 'No pending proposal';end if;
 delete from public.resolution_votes where market_id=p_market and user_id=uid;
 if not found then raise exception 'You have no vote to withdraw';end if;
 perform private.reconcile_resolution(p_market);
end $$;

-- Nullable colour keeps existing deterministic avatar assignments until a member rerolls.
alter table public.profiles add column avatar_color text check(avatar_color in ('lavender','orange','yellow','green','cyan','blue','violet','red'));
create function private.randomize_avatar() returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_member();current_color text;next_color text;hash bigint:=2166136261;i integer;colors text[]:=array['lavender','orange','yellow','green','cyan','blue','violet','red'];
begin
 select avatar_color into current_color from public.profiles where id=uid for update;
 if current_color is null then
  for i in 1..length(uid::text) loop hash:=((hash # ascii(substr(uid::text,i,1))::bigint)*16777619)%4294967296;end loop;
  current_color:=colors[1+(hash%8)::integer];
 end if;
 select color into next_color from unnest(colors) as color where color<>current_color order by random() limit 1;
 update public.profiles set avatar_color=next_color where id=uid;return next_color;
end $$;
create function public.randomize_avatar() returns text language sql security invoker set search_path='' as $$select private.randomize_avatar()$$;
revoke all on function private.create_market_v6(text,text,text,timestamptz,integer,boolean,text,text),public.create_market_v6(text,text,text,timestamptz,integer,boolean,text,text),private.randomize_avatar(),public.randomize_avatar() from public,anon,authenticated;
grant execute on function private.create_market_v6(text,text,text,timestamptz,integer,boolean,text,text),public.create_market_v6(text,text,text,timestamptz,integer,boolean,text,text),private.randomize_avatar(),public.randomize_avatar() to authenticated;
revoke all on function private.keep_execution_model(),private.reconcile_resolution(uuid) from public,anon,authenticated;
