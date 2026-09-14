-- Private account-owned social replica. Characters are simulated, not public users.
create table public.character_social_records (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check(length(id) between 1 and 160),
  kind text not null check(kind in ('world','contact','conversation','message','memory',
    'event','post','like','comment','edge','settings','budget','card','read','turn')),
  world_id text not null default 'default',
  character_id text not null default '',
  parent_id text not null default '',
  payload jsonb not null check(jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 262144),
  created_at_ms bigint not null,
  version bigint not null default 1 check(version > 0),
  deleted boolean not null default false,
  primary key(owner_user_id,id)
);
create index social_cloud_parent_time on public.character_social_records(owner_user_id,parent_id,kind,created_at_ms desc);
create index social_cloud_character on public.character_social_records(owner_user_id,character_id,kind);
create index social_cloud_world on public.character_social_records(owner_user_id,world_id,kind,created_at_ms desc);
alter table public.character_social_records enable row level security;
alter table public.character_social_records force row level security;
revoke all on public.character_social_records from anon;
grant select,insert,update on public.character_social_records to authenticated;
create policy social_owner_select on public.character_social_records for select to authenticated
  using ((select auth.uid()) = owner_user_id);
create policy social_owner_insert on public.character_social_records for insert to authenticated
  with check ((select auth.uid()) = owner_user_id);
create policy social_owner_update on public.character_social_records for update to authenticated
  using ((select auth.uid()) = owner_user_id) with check ((select auth.uid()) = owner_user_id);

-- Whole local transaction is committed or rejected. Retry of an identical write
-- returns the existing record; a stale version never overwrites a different value.
create function public.social_apply_batch(changes jsonb) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  uid uuid := auth.uid();
  change jsonb;
  current_record public.character_social_records%rowtype;
  result jsonb := '[]'::jsonb;
  conflict_found boolean := false;
begin
  if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if jsonb_typeof(changes) <> 'array' or jsonb_array_length(changes) > 100
    or octet_length(changes::text) > 1048576 then raise exception 'Invalid batch'; end if;
  if (select count(distinct value->>'id') from jsonb_array_elements(changes)) <> jsonb_array_length(changes)
    then raise exception 'Duplicate id in batch'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,7310));
  for change in select value from jsonb_array_elements(changes) loop
    select * into current_record from public.character_social_records
      where owner_user_id=uid and id=change->>'id' for update;
    if found and current_record.version <> (change->>'expected_version')::bigint
      and not (current_record.payload = change->'payload' and current_record.deleted = (change->>'deleted')::boolean
        and current_record.kind=change->>'kind' and current_record.world_id=change->>'world_id'
        and current_record.character_id=change->>'character_id' and current_record.parent_id=change->>'parent_id') then
      conflict_found := true;
    end if;
  end loop;
  if conflict_found then
    for change in select value from jsonb_array_elements(changes) loop
      select * into current_record from public.character_social_records where owner_user_id=uid and id=change->>'id';
      if found then result := result || jsonb_build_array(jsonb_build_object('accepted',false,'record',to_jsonb(current_record))); end if;
    end loop;
    return result;
  end if;
  for change in select value from jsonb_array_elements(changes) loop
    select * into current_record from public.character_social_records where owner_user_id=uid and id=change->>'id';
    if not found then
      insert into public.character_social_records(owner_user_id,id,kind,world_id,character_id,parent_id,payload,created_at_ms,deleted)
      values(uid,change->>'id',change->>'kind',change->>'world_id',change->>'character_id',change->>'parent_id',
        change->'payload',(change->>'created_at_ms')::bigint,(change->>'deleted')::boolean)
      returning * into current_record;
    elsif current_record.version = (change->>'expected_version')::bigint then
      if current_record.kind='message' and current_record.payload <> change->'payload' and not (change->>'deleted')::boolean
        then raise exception 'Messages are immutable'; end if;
      update public.character_social_records set payload=change->'payload',deleted=(change->>'deleted')::boolean,version=version+1
      where owner_user_id=uid and id=change->>'id' returning * into current_record;
    end if;
    result := result || jsonb_build_array(jsonb_build_object('accepted',true,'record',to_jsonb(current_record)));
  end loop;
  return result;
end $$;
revoke all on function public.social_apply_batch(jsonb) from public, anon;
grant execute on function public.social_apply_batch(jsonb) to authenticated;
