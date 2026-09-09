begin;
insert into auth.users(id,email) values('eeeeeeee-1000-4000-8000-000000000001','cover-rollback@example.invalid');
insert into public.profiles(id,display_name) values('eeeeeeee-1000-4000-8000-000000000001','Cover rollback') on conflict(id) do nothing;
insert into public.shared_contents(id,author_user_id,title,content_type,visibility,cover_url)
select ('eeeeeeee-1000-4000-8000-00000000001'||n)::uuid,'eeeeeeee-1000-4000-8000-000000000001','Cover rollback','OTHER',v,'eeeeeeee-1000-4000-8000-000000000001/'||n||'/cover.png'
from (values (1,'PUBLIC'),(2,'PRIVATE'),(3,'UNLISTED')) as fixtures(n,v);
insert into storage.objects(bucket_id,name)
select 'shared-previews','eeeeeeee-1000-4000-8000-000000000001/'||n||'/cover.png' from generate_series(1,4) n;
set local role anon;
do $$ begin
 if (select count(*) from storage.objects where bucket_id='shared-previews' and name like 'eeeeeeee-1000-%')<>1 then raise exception 'Anonymous cover visibility failed'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from storage.objects where bucket_id='shared-previews' and name like 'eeeeeeee-1000-%')<>1 then raise exception 'Other user cover visibility failed'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 if (select count(*) from storage.objects where bucket_id='shared-previews' and name like 'eeeeeeee-1000-%')<>4 then raise exception 'Owner cover visibility failed'; end if;
end $$;
reset role;
rollback;
select 'PASS: public bound cover only for visitors; private, unlisted and unbound covers owner-only; fixtures rolled back' as result;
