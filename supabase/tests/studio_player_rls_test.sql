-- Studio player RLS test (likes, comments, playlists, members(); migration studio_0003_player).
-- Paste into the SQL Editor of the Hub project: it always ends in an error on purpose, which rolls
-- everything back; every item in the error text must say ok.
begin;
create temp table results (check_name text, ok boolean) on commit drop;
grant insert on results to authenticated, anon;
insert into auth.users (id, aud, role, email, raw_user_meta_data)
values ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'rls-a@example.invalid', '{"full_name":"Tester A"}'),
       ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'rls-b@example.invalid', '{}'),
       ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated', 'rls-c@example.invalid', '{}');
insert into core.app_members (user_id, app_id, role)
values ('00000000-0000-4000-8000-00000000000a', 'studio', 'member'),
       ('00000000-0000-4000-8000-00000000000b', 'studio', 'member');
insert into app_studio.songs (id, created_by, title, provider, model) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000a', 'rls test A', 'test', 'test'),
  ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-00000000000b', 'rls test B', 'test', 'test');
insert into app_studio.playlists (id, created_by, name) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-00000000000b', 'B list');
insert into app_studio.song_comments (id, song_id, user_id, body) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-00000000000b', 'B says hi');

-- Member A
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into results select 'members() names A', exists (select 1 from app_studio.members() where name = 'Tester A');
insert into results select 'members() falls back to email name', exists (select 1 from app_studio.members() where name = 'rls-b');
insert into app_studio.song_likes (song_id) values ('00000000-0000-4000-8000-0000000000f2');
insert into results select 'member likes a song', count(*) = 1 from app_studio.song_likes
  where user_id = '00000000-0000-4000-8000-00000000000a';
do $$ begin
  insert into app_studio.song_likes (song_id, user_id) values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000000b');
  insert into results values ('member cannot like as someone else', false);
exception when insufficient_privilege then insert into results values ('member cannot like as someone else', true); end $$;
insert into app_studio.song_comments (song_id, body) values ('00000000-0000-4000-8000-0000000000f2', 'A comments');
insert into app_studio.song_comments (song_id, parent_id, body)
  values ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000c1', 'A replies');
insert into results select 'member comments and replies', count(*) = 2 from app_studio.song_comments
  where user_id = '00000000-0000-4000-8000-00000000000a';
do $$ begin
  insert into app_studio.song_comments (song_id, parent_id, body)
    select '00000000-0000-4000-8000-0000000000f2', id, 'reply to reply' from app_studio.song_comments where body = 'A replies';
  insert into results values ('no reply to a reply', false);
exception when raise_exception then insert into results values ('no reply to a reply', true); end $$;
do $$ begin
  insert into app_studio.song_comments (song_id, parent_id, body)
    values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000c1', 'wrong song');
  insert into results values ('no reply across songs', false);
exception when raise_exception then insert into results values ('no reply across songs', true); end $$;
with d as (delete from app_studio.song_comments where id = '00000000-0000-4000-8000-0000000000c1' returning 1)
  insert into results select 'member cannot delete others comment', count(*) = 0 from d;
insert into results select 'member sees B playlist', count(*) = 1 from app_studio.playlists where name = 'B list';
with u as (update app_studio.playlists set name = 'hacked' where id = '00000000-0000-4000-8000-0000000000b1' returning 1)
  insert into results select 'member cannot rename others playlist', count(*) = 0 from u;
do $$ begin
  insert into app_studio.playlist_songs (playlist_id, song_id) values ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1');
  insert into results values ('member cannot add to others playlist', false);
exception when insufficient_privilege then insert into results values ('member cannot add to others playlist', true); end $$;
insert into app_studio.playlists (name) values ('A list');
insert into app_studio.playlist_songs (playlist_id, song_id, position)
  select id, '00000000-0000-4000-8000-0000000000f2', 1 from app_studio.playlists where name = 'A list';
insert into results select 'member fills own playlist', count(*) = 1 from app_studio.playlist_songs ps
  join app_studio.playlists p on p.id = ps.playlist_id where p.name = 'A list';
do $$ begin
  update app_studio.songs set cover_path = 'x.svg' where id = '00000000-0000-4000-8000-0000000000f1';
  insert into results values ('member cannot set cover', false);
exception when insufficient_privilege then insert into results values ('member cannot set cover', true); end $$;
reset role;

-- Outsider C
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}', true);
set local role authenticated;
insert into results select 'outsider sees no members', count(*) = 0 from app_studio.members();
insert into results select 'outsider sees no likes', count(*) = 0 from app_studio.song_likes;
insert into results select 'outsider sees no comments', count(*) = 0 from app_studio.song_comments;
insert into results select 'outsider sees no playlists', count(*) = 0 from app_studio.playlists;
do $$ begin
  insert into app_studio.playlists (name) values ('outsider');
  insert into results values ('outsider cannot make playlist', false);
exception when insufficient_privilege then insert into results values ('outsider cannot make playlist', true); end $$;
reset role;

do $$ begin
  raise exception 'Studio player RLS test (rolled back): %',
    (select string_agg(case when ok then 'ok ' else 'FAIL ' end || check_name, '; ') from results);
end $$;
