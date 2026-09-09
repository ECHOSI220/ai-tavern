begin;
-- Existing production community tables are reused. Definitions also support a fresh database.
create table if not exists public.shared_contents (
 id uuid primary key default gen_random_uuid(), author_user_id uuid not null references public.profiles(id) on delete cascade,
 content_type text not null check(content_type in ('CHARACTER_CARD','WORLD_BOOK','CAMPAIGN_TEMPLATE','THEME_PACK','RULE_PACK','PROMPT_PACK','OTHER')),
 title text not null check(char_length(title) between 1 and 160),description text not null default '',cover_url text,
 visibility text not null default 'PRIVATE' check(visibility in ('PRIVATE','UNLISTED','PUBLIC')),
 status text not null default 'PUBLISHED' check(status in ('DRAFT','PUBLISHED','ARCHIVED','DELETED')),
 current_version integer not null default 1 check(current_version>0),download_count bigint not null default 0,view_count bigint not null default 0,
 tags text[] not null default '{}',metadata jsonb not null default '{}',forked_from_content_id uuid references public.shared_contents(id) on delete set null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),published_at timestamptz not null default now()
);
create table if not exists public.shared_content_versions (
 id uuid primary key default gen_random_uuid(),content_id uuid not null references public.shared_contents(id) on delete cascade,
 version integer not null check(version>0),schema_version integer not null default 1,file_path text not null,file_size bigint not null default 0,
 checksum text not null,changelog text not null default '',created_at timestamptz not null default now(),unique(content_id,version)
);
create table if not exists public.likes(user_id uuid not null references public.profiles(id) on delete cascade,content_id uuid not null references public.shared_contents(id) on delete cascade,created_at timestamptz not null default now(),primary key(user_id,content_id));
create table if not exists public.favorites(user_id uuid not null references public.profiles(id) on delete cascade,content_id uuid not null references public.shared_contents(id) on delete cascade,created_at timestamptz not null default now(),primary key(user_id,content_id));
create table if not exists public.comments(id uuid primary key default gen_random_uuid(),content_id uuid not null references public.shared_contents(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete cascade,parent_id uuid references public.comments(id) on delete cascade,body text not null check(char_length(body) between 1 and 5000),status text not null default 'VISIBLE',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.shared_contents enable row level security;
alter table public.shared_content_versions enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
alter table public.favorites enable row level security;
-- Remove permissive legacy community policies before installing one consistent access model.
do $$ declare p record; begin
 for p in select tablename,policyname from pg_policies where schemaname='public' and tablename in ('shared_contents','shared_content_versions','comments','likes','favorites') loop
 execute format('drop policy %I on public.%I',p.policyname,p.tablename);
 end loop;
end $$;
create policy cloud_content_read on public.shared_contents for select to anon,authenticated using ((visibility='PUBLIC' and status='PUBLISHED') or author_user_id=(select auth.uid()));
create policy cloud_content_insert on public.shared_contents for insert to authenticated with check(author_user_id=(select auth.uid()));
create policy cloud_content_delete on public.shared_contents for delete to authenticated using(author_user_id=(select auth.uid()));
create policy cloud_content_update on public.shared_contents for update to authenticated using(author_user_id=(select auth.uid())) with check(author_user_id=(select auth.uid()));
create policy cloud_version_read on public.shared_content_versions for select to anon,authenticated using(exists(select 1 from public.shared_contents c where c.id=content_id));
create policy cloud_version_insert on public.shared_content_versions for insert to authenticated with check(exists(select 1 from public.shared_contents c where c.id=content_id and c.author_user_id=(select auth.uid())) and file_path=(select auth.uid())::text||'/'||content_id::text||'/'||version::text||'.json');
-- Published version rows cannot be overwritten. Content deletion cascades versions.
grant select on public.shared_contents,public.shared_content_versions to anon;
grant select,insert,update,delete on public.shared_contents to authenticated;
grant select,insert on public.shared_content_versions to authenticated;
revoke update,delete on public.shared_content_versions from anon,authenticated;

create schema if not exists tavern_private;
revoke all on schema tavern_private from public;
grant usage on schema tavern_private to anon,authenticated;
-- UUID by-link access is deliberate; UNLISTED remains excluded from all table listings.
create or replace function tavern_private.can_read_share(share_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.shared_contents c where c.id=share_id and ((c.status='PUBLISHED' and c.visibility in ('PUBLIC','UNLISTED')) or c.author_user_id=auth.uid()));
$$;
revoke all on function tavern_private.can_read_share(uuid) from public;
grant execute on function tavern_private.can_read_share(uuid) to anon,authenticated;
create policy cloud_comments_read on public.comments for select to anon,authenticated using((status='VISIBLE' and exists(select 1 from public.shared_contents c where c.id=content_id)) or user_id=(select auth.uid()));
create policy cloud_comments_insert on public.comments for insert to authenticated with check(user_id=(select auth.uid()) and status='VISIBLE' and parent_id is null and tavern_private.can_read_share(content_id));
create policy cloud_comments_delete on public.comments for delete to authenticated using(user_id=(select auth.uid()));
grant select on public.comments to anon;
grant select,insert,delete on public.comments to authenticated;
revoke update on public.comments from anon,authenticated;
create policy cloud_likes_read on public.likes for select to authenticated using(user_id=(select auth.uid()));
create policy cloud_likes_insert on public.likes for insert to authenticated with check(user_id=(select auth.uid()) and tavern_private.can_read_share(content_id));
create policy cloud_likes_delete on public.likes for delete to authenticated using(user_id=(select auth.uid()));
create policy cloud_favorites_read on public.favorites for select to authenticated using(user_id=(select auth.uid()));
create policy cloud_favorites_insert on public.favorites for insert to authenticated with check(user_id=(select auth.uid()) and tavern_private.can_read_share(content_id));
create policy cloud_favorites_delete on public.favorites for delete to authenticated using(user_id=(select auth.uid()));
grant select,insert,delete on public.likes,public.favorites to authenticated;

create or replace function public.cloud_share_by_id(share_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('content',to_jsonb(c),'versions',coalesce((select jsonb_agg(to_jsonb(v) order by v.version desc) from public.shared_content_versions v where v.content_id=c.id),'[]'::jsonb),'comments',coalesce((select jsonb_agg(to_jsonb(x)) from (select body,created_at from public.comments where content_id=c.id and status='VISIBLE' order by created_at desc limit 100)x),'[]'::jsonb))
 from public.shared_contents c where c.id=share_id and tavern_private.can_read_share(c.id);
$$;
revoke all on function public.cloud_share_by_id(uuid) from public;
grant execute on function public.cloud_share_by_id(uuid) to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('shared-content','shared-content',false,2000000,array['application/json']),
 ('shared-previews','shared-previews',false,5000000,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing;
create policy cloud_object_insert on storage.objects for insert to authenticated with check(bucket_id in ('shared-content','shared-previews') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy cloud_object_owner_read on storage.objects for select to authenticated using(bucket_id in ('shared-content','shared-previews') and (storage.foldername(name))[1]=(select auth.uid())::text);
-- No UPDATE: immutable version objects cannot be replaced by upsert.
create policy cloud_object_unused_delete on storage.objects for delete to authenticated using(bucket_id in ('shared-content','shared-previews') and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.shared_content_versions v where v.file_path=name));
create or replace function tavern_private.can_download_share(path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.shared_content_versions v where v.file_path=path and tavern_private.can_read_share(v.content_id));
$$;
revoke all on function tavern_private.can_download_share(text) from public;
grant execute on function tavern_private.can_download_share(text) to anon,authenticated;
create policy cloud_object_content_read on storage.objects for select to anon,authenticated using(bucket_id='shared-content' and tavern_private.can_download_share(name));

create or replace function public.cloud_publish_share(share_id uuid,share_title text,share_description text,share_type text,share_visibility text,share_tags text[],object_path text,object_size bigint,object_checksum text) returns uuid
language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or object_path<>auth.uid()::text||'/'||share_id::text||'/1.json' or object_size not between 1 and 2000000 or object_checksum !~ '^[0-9a-f]{64}$' or char_length(share_description)>2000 or cardinality(share_tags)>8 then raise exception 'Invalid share package';end if;
 if not exists(select 1 from storage.objects where bucket_id='shared-content' and name=object_path) then raise exception 'Upload missing';end if;
 insert into public.shared_contents(id,author_user_id,title,description,content_type,visibility,tags) values(share_id,auth.uid(),share_title,share_description,share_type,share_visibility,share_tags);
 insert into public.shared_content_versions(content_id,version,schema_version,file_path,file_size,checksum) values(share_id,1,1,object_path,object_size,object_checksum);
 return share_id;
end $$;
revoke all on function public.cloud_publish_share(uuid,text,text,text,text,text[],text,bigint,text) from public;
grant execute on function public.cloud_publish_share(uuid,text,text,text,text,text[],text,bigint,text) to authenticated;
-- Legacy policy had r.room_id=r.room_id: any room owner could overwrite other rooms.
-- Public snapshots are now server-authored only; no app client needs to write them.
do $$ begin
 if to_regclass('public.public_room_snapshots') is not null then
 execute 'revoke insert,update,delete on public.public_room_snapshots from anon,authenticated';
 end if;
end $$;
create index if not exists cloud_content_discover on public.shared_contents(visibility,status,created_at desc);
create index if not exists cloud_content_author on public.shared_contents(author_user_id,created_at desc);
create index if not exists cloud_comment_content on public.comments(content_id,created_at desc);
commit;
