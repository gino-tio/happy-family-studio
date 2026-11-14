-- Studio RLS test (paste into the SQL Editor of the Hub project): always ends in an error on purpose, which rolls everything back; every item in the error text must say ok.
begin;
create temp table results (check_name text, ok boolean) on commit drop;
grant insert on results to authenticated, anon;
insert into auth.users (id, aud, role, email)
values ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'rls-a@example.invalid'),
       ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'rls-b@example.invalid'),
       ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated', 'rls-c@example.invalid');
insert into core.app_members (user_id, app_id, role)
values ('00000000-0000-4000-8000-00000000000a', 'studio', 'member'),
       ('00000000-0000-4000-8000-00000000000b', 'studio', 'member');
-- Songs are written by the Edge Function (service role); here the SQL Editor stands in for it.
insert into app_studio.songs (id, created_by, title, provider, model) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', 'rls test A', 'test', 'test'),
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-00000000000b', 'rls test B', 'test', 'test');

-- Member A
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into results select 'member sees all test songs', count(*) = 2 from app_studio.songs where title like 'rls test %';
insert into results select 'member is member', app_studio.me() = 'member';
with u as (update app_studio.songs set title = 'renamed' where id = '00000000-0000-4000-8000-0000000000f1' returning 1)
  insert into results select 'member renames own song', count(*) = 1 from u;
with u as (update app_studio.songs set title = 'hacked' where id = '00000000-0000-4000-8000-0000000000f2' returning 1)
  insert into results select 'member cannot rename others', count(*) = 0 from u;
with d as (delete from app_studio.songs where id = '00000000-0000-4000-8000-0000000000f2' returning 1)
  insert into results select 'member cannot delete others', count(*) = 0 from d;
do $$ begin
  insert into app_studio.songs (created_by, title, provider, model)
    values ('00000000-0000-4000-8000-00000000000a', 'x', 'x', 'x');
  insert into results values ('member cannot insert', false);
exception when insufficient_privilege then insert into results values ('member cannot insert', true); end $$;
do $$ begin
  update app_studio.songs set status = 'done' where id = '00000000-0000-4000-8000-0000000000f1';
  insert into results values ('member cannot change status', false);
exception when insufficient_privilege then insert into results values ('member cannot change status', true); end $$;
with d as (delete from app_studio.songs where id = '00000000-0000-4000-8000-0000000000f1' returning 1)
  insert into results select 'member deletes own song', count(*) = 1 from d;
reset role;

-- Outsider C
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}', true);
set local role authenticated;
insert into results select 'outsider sees no songs', count(*) = 0 from app_studio.songs;
insert into results select 'outsider is not member', app_studio.me() is null;
reset role;

set local role anon;
do $$ begin
  perform 1 from app_studio.songs;
  insert into results values ('anon blocked', false);
exception when insufficient_privilege then insert into results values ('anon blocked', true); end $$;
reset role;

do $$ begin
  raise exception 'Studio RLS test (rolled back): %',
    (select string_agg(case when ok then 'ok ' else 'FAIL ' end || check_name, '; ') from results);
end $$;
