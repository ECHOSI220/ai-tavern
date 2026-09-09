begin;
-- Keep the intentionally privileged by-link reader outside exposed schemas.
alter function public.cloud_share_by_id(uuid) set schema tavern_private;
create function public.cloud_share_by_id(share_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select tavern_private.cloud_share_by_id(share_id);
$$;
revoke all on function public.cloud_share_by_id(uuid) from public;
grant execute on function public.cloud_share_by_id(uuid) to anon,authenticated;
commit;
