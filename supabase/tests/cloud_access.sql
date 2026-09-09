-- Transactional fixtures: no test content or users survive this test.
begin;
insert into auth.users(id,email) values('eeeeeeee-0000-4000-8000-000000000001','cloud-test-rollback@example.invalid');
insert into public.profiles(id,display_name) values('eeeeeeee-0000-4000-8000-000000000001','Rollback fixture') on conflict(id) do nothing;
insert into public.shared_contents(id,author_user_id,title,content_type,visibility) values
 ('eeeeeeee-0000-4000-8000-000000000011','eeeeeeee-0000-4000-8000-000000000001','Rollback public','OTHER','PUBLIC'),
 ('eeeeeeee-0000-4000-8000-000000000012','eeeeeeee-0000-4000-8000-000000000001','Rollback unlisted','OTHER','UNLISTED'),
 ('eeeeeeee-0000-4000-8000-000000000013','eeeeeeee-0000-4000-8000-000000000001','Rollback private','OTHER','PRIVATE');
insert into public.shared_content_versions(content_id,version,file_path,checksum) values
 ('eeeeeeee-0000-4000-8000-000000000011',1,'eeeeeeee-0000-4000-8000-000000000001/eeeeeeee-0000-4000-8000-000000000011/1.json',repeat('a',64)),
 ('eeeeeeee-0000-4000-8000-000000000012',1,'eeeeeeee-0000-4000-8000-000000000001/eeeeeeee-0000-4000-8000-000000000012/1.json',repeat('a',64));
set local role anon;
do $$ begin
 if (select count(*) from public.shared_contents where id::text like 'eeeeeeee-%')<>1 then raise exception 'Anonymous listing leaked private or unlisted content';end if;
 if public.cloud_share_by_id('eeeeeeee-0000-4000-8000-000000000012') is null then raise exception 'Unlisted link inaccessible';end if;
 if public.cloud_share_by_id('eeeeeeee-0000-4000-8000-000000000013') is not null then raise exception 'Private link leaked';end if;
 if tavern_private.can_download_share('eeeeeeee-0000-4000-8000-000000000001/eeeeeeee-0000-4000-8000-000000000012/1.json') then raise exception 'Storage can enumerate unlisted objects';end if;
 if not tavern_private.can_download_share('eeeeeeee-0000-4000-8000-000000000001/eeeeeeee-0000-4000-8000-000000000011/1.json') then raise exception 'Public file inaccessible';end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.shared_contents where id::text like 'eeeeeeee-%')<>3 then raise exception 'Author cannot see own content';end if;
 if public.cloud_share_by_id('eeeeeeee-0000-4000-8000-000000000013') is null then raise exception 'Author private read failed';end if;
 if not tavern_private.can_download_share('eeeeeeee-0000-4000-8000-000000000001/eeeeeeee-0000-4000-8000-000000000012/1.json') then raise exception 'Author unlisted download failed';end if;
 if has_table_privilege(current_user,'public.shared_content_versions','UPDATE') then raise exception 'Versions are mutable';end if;
 if has_table_privilege(current_user,'public.public_room_snapshots','UPDATE') then raise exception 'Clients can forge room snapshots';end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if public.cloud_share_by_id('eeeeeeee-0000-4000-8000-000000000013') is not null then raise exception 'Other user can read private content';end if;
 delete from public.shared_contents where id='eeeeeeee-0000-4000-8000-000000000011';
 if not exists(select 1 from public.shared_contents where id='eeeeeeee-0000-4000-8000-000000000011') then raise exception 'Other user deleted content';end if;
end $$;
rollback;
select 'PASS: anonymous, owner, other-user, immutable-version and room-write boundaries' as result;
