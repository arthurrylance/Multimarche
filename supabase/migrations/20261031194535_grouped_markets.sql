-- One group heading, with independent binary markets and independent financial reserves.
create table public.market_groups(
 id uuid primary key default gen_random_uuid(),creator_id uuid not null references public.profiles(id),title text not null check(title ~ '[^[:space:]]'),
 request_id uuid not null unique,creation_hash text not null,created_at timestamptz not null default now()
);
create index market_groups_creator_idx on public.market_groups(creator_id);
alter table public.markets add column group_id uuid references public.market_groups(id);
alter table public.markets add column option_label text;
alter table public.markets add column group_position integer;
alter table public.markets add constraint market_group_option check((group_id is null and option_label is null and group_position is null) or (group_id is not null and option_label is not null and option_label ~ '[^[:space:]]' and group_position>=0 and group_position is not null));
create unique index markets_group_position_idx on public.markets(group_id,group_position) where group_id is not null;
alter table public.market_groups enable row level security;
create policy member_market_groups on public.market_groups for select to authenticated using((select private.is_member()) and exists(select 1 from public.markets m where m.group_id=market_groups.id));
revoke all on public.market_groups from public,anon,authenticated;
grant select on public.market_groups to authenticated;
alter publication supabase_realtime add table public.market_groups;

-- Preserve group identity and keep option labels in sync when an admin edits a child question.
create function private.grouped_market_identity() returns trigger language plpgsql security definer set search_path='' as $$
declare heading text;prefix text;label text;
begin
 if old.group_id is not null and (new.group_id is distinct from old.group_id or new.group_position is distinct from old.group_position) then raise exception 'An option cannot move between groups';end if;
 if new.group_id is null then return new;end if;
 select title into heading from public.market_groups where id=new.group_id;
 if not found then raise exception 'Unknown market group';end if;
 prefix:=heading||' · ';
 if new.option_label is distinct from old.option_label and new.title=old.title then label:=btrim(new.option_label);
 else label:=btrim(case when left(new.title,length(prefix))=prefix then substr(new.title,length(prefix)+1) else new.title end);end if;
 if label is null or label !~ '[^[:space:]]' then raise exception 'An option needs a label';end if;
 new.option_label:=label;new.title:=prefix||label;return new;
end $$;
create trigger grouped_market_identity before update of title,group_id,option_label,group_position on public.markets for each row execute function private.grouped_market_identity();

create function private.create_market_group(p_title text,p_options jsonb,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.require_player();g public.market_groups;spec text;item jsonb;label text;yr text;nr text;mid uuid;ids jsonb:='[]';position integer:=0;remaining integer;
begin
 perform pg_advisory_xact_lock(84271001);
 if p_request is null then raise exception 'A request ID is required';end if;
 spec:=encode(extensions.digest(jsonb_build_object('title',p_title,'options',p_options,'closes',p_closes,'verifications',p_verifications,'counter',p_counter,'counter_label',p_counter_label,'execution',p_execution)::text,'sha256'),'hex');
 select * into g from public.market_groups where request_id=p_request;
 if found then
  if g.creator_id<>uid or g.creation_hash<>spec then raise exception 'Request ID already used for a different group';end if;
  select coalesce(jsonb_agg(id order by group_position),'[]'::jsonb) into ids from public.markets where group_id=g.id;
  return jsonb_build_object('group_id',g.id,'market_ids',ids);
 end if;
 if p_title is null or p_title !~ '[^[:space:]]' then raise exception 'A group question is required';end if;
 if p_options is null or jsonb_typeof(p_options)<>'array' then raise exception 'Add 2 to 10 options';end if;
 if jsonb_array_length(p_options)<2 or jsonb_array_length(p_options)>10 then raise exception 'Add 2 to 10 options';end if;
 for item in select value from jsonb_array_elements(p_options) loop
  if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'label') is distinct from 'string' or (item->>'label') !~ '[^[:space:]]' then raise exception 'Each option needs a label';end if;
  if (item ? 'yes' and jsonb_typeof(item->'yes') not in ('string','null')) or (item ? 'no' and jsonb_typeof(item->'no') not in ('string','null')) then raise exception 'Option meanings must be text';end if;
 end loop;
 if (select count(distinct lower(btrim(value->>'label'))) from jsonb_array_elements(p_options))<>jsonb_array_length(p_options) then raise exception 'Use a different label for each option';end if;
 select greatest(0,10-count(*)) into remaining from public.markets where creator_id=uid and created_at>now()-interval '1 day';
 if jsonb_array_length(p_options)>remaining then raise exception 'You can create % more options today; each option counts toward the daily market limit',remaining;end if;
 insert into public.market_groups(creator_id,title,request_id,creation_hash) values(uid,btrim(p_title),p_request,spec) returning * into g;
 for item in select value from jsonb_array_elements(p_options) loop
  label:=btrim(item->>'label');yr:=coalesce(nullif(btrim(item->>'yes'),''),'“'||label||'” happens during this event.');nr:=coalesce(nullif(btrim(item->>'no'),''),'“'||label||'” does not happen during this event.');
  mid:=private.create_market_v6(g.title||' · '||label,yr,nr,p_closes,p_verifications,p_counter,p_counter_label,p_execution);
  update public.markets set group_id=g.id,option_label=label,group_position=position where id=mid;
  ids:=ids||jsonb_build_array(mid);position:=position+1;
 end loop;
 return jsonb_build_object('group_id',g.id,'market_ids',ids);
end $$;
create function public.create_market_group(p_title text,p_options jsonb,p_closes timestamptz,p_verifications integer,p_counter boolean,p_counter_label text,p_execution text,p_request uuid) returns jsonb language sql security invoker set search_path='' as $$select private.create_market_group(p_title,p_options,p_closes,p_verifications,p_counter,p_counter_label,p_execution,p_request)$$;
revoke all on function private.grouped_market_identity(),private.create_market_group(text,jsonb,timestamptz,integer,boolean,text,text,uuid),public.create_market_group(text,jsonb,timestamptz,integer,boolean,text,text,uuid) from public,anon,authenticated;
grant execute on function private.create_market_group(text,jsonb,timestamptz,integer,boolean,text,text,uuid),public.create_market_group(text,jsonb,timestamptz,integer,boolean,text,text,uuid) to authenticated;
