begin;
-- Storage list uses the same SELECT policy as download. Allowing UNLISTED
-- here would expose unlisted object names through bucket listing.
create or replace function tavern_private.can_download_share(path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.shared_content_versions v join public.shared_contents c on c.id=v.content_id where v.file_path=path and ((c.visibility='PUBLIC' and c.status='PUBLISHED') or c.author_user_id=auth.uid()));
$$;
commit;
