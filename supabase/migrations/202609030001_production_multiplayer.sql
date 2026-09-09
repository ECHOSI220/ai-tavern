begin;

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '旅行者' check (char_length(display_name) between 1 and 40),
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120), description text not null default '',
  template_id text, rule_pack_id text not null default 'simple_trpg', rule_pack_version integer not null default 1,
  world_snapshot_version integer not null default 1, save_version integer not null default 1,
  visibility text not null default 'private' check (visibility in ('private','invite_only','friends','public')),
  state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.campaign_members (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner','gm','player','viewer')), joined_at timestamptz not null default now(),
  primary key (campaign_id, user_id)
);

create table if not exists public.campaign_saves (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references public.campaigns(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade, created_by uuid not null references public.profiles(id) on delete cascade,
  revision bigint not null default 0, label text not null default '自动存档', schema_version integer not null default 1,
  rule_pack_version integer not null default 1, world_version integer not null default 1, save_version integer not null default 1,
  snapshot jsonb not null, checksum text not null, created_at timestamptz not null default now()
);

create table if not exists public.room_metadata (
  room_id uuid primary key, room_code text not null unique check (room_code ~ '^[A-HJ-NP-Z2-9]{5,8}$'),
  owner_user_id uuid not null references public.profiles(id) on delete cascade, campaign_id text not null,
  room_name text not null, status text not null default 'lobby' check (status in ('lobby','starting','playing','paused','finished','closed')),
  max_players integer not null check (max_players between 2 and 8), current_players integer not null default 1,
  server_region text not null default 'auto', last_revision bigint not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.multiplayer_checkpoints (
  room_id uuid primary key references public.room_metadata(room_id) on delete cascade, campaign_id text not null,
  revision bigint not null, snapshot jsonb not null, updated_at timestamptz not null default now()
);

create table if not exists public.friendships (
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','blocked')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (requester_id, addressee_id), check (requester_id <> addressee_id)
);

create table if not exists public.room_invites (
  id uuid primary key default gen_random_uuid(), room_id uuid not null references public.room_metadata(room_id) on delete cascade,
  inviter_id uuid not null references public.profiles(id) on delete cascade, invitee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','expired')),
  expires_at timestamptz not null default (now() + interval '24 hours'), created_at timestamptz not null default now()
);

create table if not exists public.game_event_logs (
  id bigint generated always as identity primary key, room_id uuid not null references public.room_metadata(room_id) on delete cascade,
  revision bigint not null, event_type text not null, actor_user_id uuid references public.profiles(id) on delete set null,
  audit_payload jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create index if not exists campaigns_owner_updated_idx on public.campaigns(owner_id, updated_at desc);
create index if not exists campaign_members_user_idx on public.campaign_members(user_id);
create index if not exists campaign_members_campaign_idx on public.campaign_members(campaign_id);
create index if not exists campaign_saves_campaign_revision_idx on public.campaign_saves(campaign_id, revision desc);
create index if not exists room_metadata_owner_updated_idx on public.room_metadata(owner_user_id, updated_at desc);
create index if not exists room_metadata_campaign_idx on public.room_metadata(campaign_id);
create index if not exists room_invites_invitee_status_idx on public.room_invites(invitee_id, status);
create index if not exists game_event_logs_room_revision_idx on public.game_event_logs(room_id, revision);

alter table public.profiles enable row level security;
alter table public.campaigns enable row level security;
alter table public.campaign_members enable row level security;
alter table public.campaign_saves enable row level security;
alter table public.room_metadata enable row level security;
alter table public.multiplayer_checkpoints enable row level security;
alter table public.friendships enable row level security;
alter table public.room_invites enable row level security;
alter table public.game_event_logs enable row level security;

revoke all on public.profiles, public.campaigns, public.campaign_members,
  public.campaign_saves, public.room_metadata, public.multiplayer_checkpoints,
  public.friendships, public.room_invites, public.game_event_logs from anon;
grant usage on schema public to authenticated;
grant select, insert, update on public.profiles, public.campaigns, public.campaign_members, public.campaign_saves, public.friendships, public.room_invites to authenticated;
grant select on public.room_metadata to authenticated;

create or replace function public.is_campaign_member(target uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.campaign_members where campaign_id = target and user_id = auth.uid())
$$;

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles for select to authenticated using (true);
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists campaigns_member_read on public.campaigns;
create policy campaigns_member_read on public.campaigns for select to authenticated using (owner_id = auth.uid() or public.is_campaign_member(id));
drop policy if exists campaigns_owner_write on public.campaigns;
create policy campaigns_owner_write on public.campaigns for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists campaign_members_member_read on public.campaign_members;
create policy campaign_members_member_read on public.campaign_members for select to authenticated using (user_id = auth.uid() or public.is_campaign_member(campaign_id));
drop policy if exists campaign_members_owner_write on public.campaign_members;
create policy campaign_members_owner_write on public.campaign_members for all to authenticated using (exists(select 1 from public.campaigns c where c.id = campaign_id and c.owner_id = auth.uid())) with check (exists(select 1 from public.campaigns c where c.id = campaign_id and c.owner_id = auth.uid()));
drop policy if exists campaign_saves_member_read on public.campaign_saves;
create policy campaign_saves_member_read on public.campaign_saves for select to authenticated using (owner_id = auth.uid() or public.is_campaign_member(campaign_id));
drop policy if exists campaign_saves_owner_write on public.campaign_saves;
create policy campaign_saves_owner_write on public.campaign_saves for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists room_metadata_authenticated_read on public.room_metadata;
create policy room_metadata_authenticated_read on public.room_metadata for select to authenticated using (status not in ('closed'));
drop policy if exists friendships_participant on public.friendships;
create policy friendships_participant on public.friendships for all to authenticated using (auth.uid() in (requester_id, addressee_id)) with check (auth.uid() = requester_id);
drop policy if exists invites_participant on public.room_invites;
create policy invites_participant on public.room_invites for select to authenticated using (auth.uid() in (inviter_id, invitee_id));
drop policy if exists invites_create_self on public.room_invites;
create policy invites_create_self on public.room_invites for insert to authenticated with check (auth.uid() = inviter_id);
drop policy if exists invites_update_recipient on public.room_invites;
create policy invites_update_recipient on public.room_invites for update to authenticated using (auth.uid() = invitee_id) with check (auth.uid() = invitee_id);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles(id, display_name) values(new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(coalesce(new.email,'旅行者'),'@',1))) on conflict (id) do nothing; return new; end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars','avatars',false,5242880,array['image/png','image/jpeg','image/webp']),
  ('campaign-assets','campaign-assets',false,52428800,array['image/png','image/jpeg','image/webp','audio/mpeg','audio/ogg','application/json'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatar_read_authenticated on storage.objects;
create policy avatar_read_authenticated on storage.objects for select to authenticated using (bucket_id = 'avatars');
drop policy if exists avatar_owner_write on storage.objects;
create policy avatar_owner_write on storage.objects for all to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists campaign_assets_owner_read on storage.objects;
create policy campaign_assets_owner_read on storage.objects for select to authenticated using (bucket_id = 'campaign-assets' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists campaign_assets_owner_write on storage.objects;
create policy campaign_assets_owner_write on storage.objects for all to authenticated using (bucket_id = 'campaign-assets' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'campaign-assets' and (storage.foldername(name))[1] = auth.uid()::text);

commit;
