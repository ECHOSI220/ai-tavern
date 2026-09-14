create table public.character_social_ai_budget (
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  calls integer not null default 0 check(calls between 0 and 50),
  primary key(owner_user_id,day)
);
alter table public.character_social_ai_budget enable row level security;
alter table public.character_social_ai_budget force row level security;
revoke all on public.character_social_ai_budget from anon;
grant select,insert,update on public.character_social_ai_budget to authenticated;
create policy social_budget_owner on public.character_social_ai_budget for all to authenticated
  using((select auth.uid())=owner_user_id) with check((select auth.uid())=owner_user_id);
create function public.social_reserve_ai_call(max_calls integer) returns integer
language plpgsql security invoker set search_path='' as $$
declare result integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if max_calls < 1 or max_calls > 50 then raise exception 'Automatic AI budget exhausted'; end if;
  insert into public.character_social_ai_budget(owner_user_id,day,calls)
    values(auth.uid(),timezone('UTC',now())::date,1)
  on conflict(owner_user_id,day) do update set calls=public.character_social_ai_budget.calls+1
    where public.character_social_ai_budget.calls<max_calls
  returning calls into result;
  if result is null then raise exception 'Automatic AI budget exhausted'; end if;
  return result;
end $$;
revoke all on function public.social_reserve_ai_call(integer) from public,anon;
grant execute on function public.social_reserve_ai_call(integer) to authenticated;
