begin;

-- Publish the immutable JSON and its optional cover in one database transaction.
-- The bucket is private; public covers are exposed only through a short-lived signed URL.
create or replace function public.cloud_publish_share_with_preview(
  share_id uuid,
  share_title text,
  share_description text,
  share_type text,
  share_visibility text,
  share_tags text[],
  object_path text,
  object_size bigint,
  object_checksum text,
  preview_path text
) returns uuid
language plpgsql
security invoker
set search_path=''
as $$
begin
  if auth.uid() is null
    or object_path <> auth.uid()::text||'/'||share_id::text||'/1.json'
    or object_size not between 1 and 2000000
    or object_checksum !~ '^[0-9a-f]{64}$'
    or char_length(share_description) > 2000
    or cardinality(share_tags) > 8
    or preview_path not in (
      auth.uid()::text||'/'||share_id::text||'/cover.png',
      auth.uid()::text||'/'||share_id::text||'/cover.jpg',
      auth.uid()::text||'/'||share_id::text||'/cover.webp'
    )
  then
    raise exception 'Invalid share package or preview';
  end if;

  if not exists(
    select 1 from storage.objects
    where bucket_id='shared-content' and name=object_path
  ) or not exists(
    select 1 from storage.objects
    where bucket_id='shared-previews' and name=preview_path
  ) then
    raise exception 'Upload missing';
  end if;

  insert into public.shared_contents(
    id,author_user_id,title,description,content_type,visibility,tags,cover_url
  ) values(
    share_id,auth.uid(),share_title,share_description,share_type,
    share_visibility,share_tags,preview_path
  );
  insert into public.shared_content_versions(
    content_id,version,schema_version,file_path,file_size,checksum
  ) values(share_id,1,1,object_path,object_size,object_checksum);
  return share_id;
end
$$;

revoke all on function public.cloud_publish_share_with_preview(
  uuid,text,text,text,text,text[],text,bigint,text,text
) from public;
grant execute on function public.cloud_publish_share_with_preview(
  uuid,text,text,text,text,text[],text,bigint,text,text
) to authenticated;

-- Publicly listed works may request signed cover URLs. Owner-only and unlisted
-- previews stay protected by the existing owner policy.
create policy cloud_object_preview_public_read
on storage.objects for select to anon,authenticated
using(
  bucket_id='shared-previews'
  and exists(
    select 1 from public.shared_contents c
    where c.cover_url=storage.objects.name
      and c.visibility='PUBLIC'
      and c.status='PUBLISHED'
  )
);

commit;
