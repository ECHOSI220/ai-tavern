begin;

-- Canonical snapshots contain GM secrets. Membership is NOT permission to
-- download a canonical snapshot; players receive a filtered view through the DO.
drop policy if exists campaigns_member_read on public.campaigns;
create policy campaigns_member_read on public.campaigns for select to authenticated
  using (owner_id = auth.uid());
drop policy if exists campaign_saves_member_read on public.campaign_saves;
create policy campaign_saves_member_read on public.campaign_saves for select to authenticated
  using (owner_id = auth.uid() and exists (
    select 1 from public.campaigns c where c.id = campaign_id and c.owner_id = auth.uid()
  ));
drop policy if exists campaign_saves_owner_write on public.campaign_saves;
create policy campaign_saves_owner_write on public.campaign_saves for insert to authenticated
  with check (owner_id = auth.uid() and created_by = auth.uid() and exists (
    select 1 from public.campaigns c where c.id = campaign_id and c.owner_id = auth.uid()
  ));
revoke update on public.campaign_saves from authenticated;

-- Joining is a rate-limited code lookup at the Worker, not a browsable directory.
drop policy if exists room_metadata_authenticated_read on public.room_metadata;
create policy room_metadata_authenticated_read on public.room_metadata for select to authenticated
  using (owner_user_id = auth.uid());

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles for select to authenticated
  using (id = auth.uid() or exists (
    select 1 from public.friendships f where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = profiles.id)
        or (f.addressee_id = auth.uid() and f.requester_id = profiles.id))
  ));
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_path) on public.profiles to authenticated;

drop policy if exists friendships_participant on public.friendships;
create policy friendships_read on public.friendships for select to authenticated
  using (auth.uid() in (requester_id, addressee_id));
create policy friendships_request on public.friendships for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending');
create policy friendships_answer on public.friendships for update to authenticated
  using (addressee_id = auth.uid()) with check (addressee_id = auth.uid() and status in ('accepted', 'blocked'));
create policy friendships_remove on public.friendships for delete to authenticated
  using (auth.uid() in (requester_id, addressee_id));
revoke update on public.friendships from authenticated;
grant update (status) on public.friendships to authenticated;
grant delete on public.friendships to authenticated;

drop policy if exists invites_create_self on public.room_invites;
create policy invites_create_self on public.room_invites for insert to authenticated
  with check (inviter_id = auth.uid() and invitee_id <> auth.uid() and status = 'pending'
    and expires_at > now() and expires_at <= now() + interval '24 hours'
    and exists (select 1 from public.room_metadata r
      where r.room_id = room_invites.room_id and r.owner_user_id = auth.uid() and r.status = 'lobby'));
drop policy if exists invites_update_recipient on public.room_invites;
create policy invites_update_recipient on public.room_invites for update to authenticated
  using (invitee_id = auth.uid() and status = 'pending' and expires_at > now())
  with check (invitee_id = auth.uid() and status in ('accepted', 'declined'));
revoke update on public.room_invites from authenticated;
grant update (status) on public.room_invites to authenticated;

-- Concurrent HTTP checkpoint requests must never overwrite a newer revision.
create or replace function public.save_multiplayer_checkpoint(
  target_room uuid, target_campaign text, target_revision bigint, target_snapshot jsonb
) returns void language sql security invoker set search_path = public as $$
  insert into public.multiplayer_checkpoints(room_id, campaign_id, revision, snapshot, updated_at)
  values (target_room, target_campaign, target_revision, target_snapshot, now())
  on conflict (room_id) do update set
    campaign_id = excluded.campaign_id, revision = excluded.revision,
    snapshot = excluded.snapshot, updated_at = excluded.updated_at
  where public.multiplayer_checkpoints.revision <= excluded.revision;
$$;
revoke all on function public.save_multiplayer_checkpoint(uuid, text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.save_multiplayer_checkpoint(uuid, text, bigint, jsonb) to service_role;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''), '旅行者'), 40))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

commit;
