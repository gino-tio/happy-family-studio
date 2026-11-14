-- studio_0003_player: covers, timed lyrics, likes, comments and playlists (Gino, 2026-11-14:
-- "redesign like musicgpt.com", all recommended answers). Shared-DB rules as in 0001: everything in
-- app_studio, every policy checks core.is_member('studio') first. Safe to re-run.
--
--   songs.cover_path     object in the private studio-covers bucket (MusicGPT's own cover as .jpg,
--                        or a picture Claude draws through the Hub as .svg). Written by Edge
--                        Functions only, like status / audio_path.
--   songs.lyrics_timed   [{start, end, text}] in ms, from MusicGPT's lyrics timestamps; the app
--                        highlights the line being sung. Null = show the plain lyrics.
--   song_likes           one heart per member per song ("我鍾意" is the member's likes).
--   song_comments        family comments; a reply points at a top-level comment (one level).
--   playlists            every member sees and plays every playlist; only its maker changes it.
--   members()            names and avatars of the band, for comments and "by" lines.

alter table app_studio.songs add column if not exists cover_path text;
alter table app_studio.songs add column if not exists lyrics_timed jsonb;
alter table app_studio.songs drop constraint if exists songs_lyrics_timed_array;
alter table app_studio.songs add constraint songs_lyrics_timed_array
  check (lyrics_timed is null or jsonb_typeof(lyrics_timed) = 'array');

-- AI covers count against a daily quota like lyrics.
alter table app_studio.ai_usage drop constraint if exists ai_usage_kind_check;
alter table app_studio.ai_usage add constraint ai_usage_kind_check check (kind in ('lyrics', 'cover'));

-- Band members with a display name, for comment and song "by" lines. Only members get rows.
create or replace function app_studio.members()
returns table (user_id uuid, name text, avatar_url text, role text)
language sql stable security definer set search_path = '' as $$
  select m.user_id,
         coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''),
                  nullif(u.raw_user_meta_data ->> 'name', ''),
                  split_part(u.email, '@', 1)),
         nullif(u.raw_user_meta_data ->> 'avatar_url', ''),
         m.role
  from core.app_members m
  join auth.users u on u.id = m.user_id
  where m.app_id = 'studio' and core.is_member('studio');
$$;
revoke all on function app_studio.members() from public, anon;
grant execute on function app_studio.members() to authenticated;

-- Likes -------------------------------------------------------------------------------------
create table if not exists app_studio.song_likes (
  song_id    uuid not null references app_studio.songs (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (song_id, user_id)
);
create index if not exists song_likes_user_idx on app_studio.song_likes (user_id, created_at desc);
alter table app_studio.song_likes enable row level security;
revoke all on app_studio.song_likes from anon, authenticated;
grant select, delete on app_studio.song_likes to authenticated;
grant insert (song_id) on app_studio.song_likes to authenticated;
drop policy if exists song_likes_select on app_studio.song_likes;
drop policy if exists song_likes_insert on app_studio.song_likes;
drop policy if exists song_likes_delete on app_studio.song_likes;
create policy song_likes_select on app_studio.song_likes for select to authenticated
  using ((select core.is_member('studio')));
create policy song_likes_insert on app_studio.song_likes for insert to authenticated
  with check ((select core.is_member('studio')) and user_id = (select auth.uid()));
create policy song_likes_delete on app_studio.song_likes for delete to authenticated
  using ((select core.is_member('studio')) and user_id = (select auth.uid()));

-- Comments ----------------------------------------------------------------------------------
create table if not exists app_studio.song_comments (
  id         uuid primary key default gen_random_uuid(),
  song_id    uuid not null references app_studio.songs (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  parent_id  uuid references app_studio.song_comments (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists song_comments_song_idx on app_studio.song_comments (song_id, created_at);
create index if not exists song_comments_parent_idx on app_studio.song_comments (parent_id);
create index if not exists song_comments_user_idx on app_studio.song_comments (user_id);
alter table app_studio.song_comments enable row level security;
revoke all on app_studio.song_comments from anon, authenticated;
grant select, delete on app_studio.song_comments to authenticated;
grant insert (song_id, parent_id, body) on app_studio.song_comments to authenticated;
drop policy if exists song_comments_select on app_studio.song_comments;
drop policy if exists song_comments_insert on app_studio.song_comments;
drop policy if exists song_comments_delete on app_studio.song_comments;
create policy song_comments_select on app_studio.song_comments for select to authenticated
  using ((select core.is_member('studio')));
create policy song_comments_insert on app_studio.song_comments for insert to authenticated
  with check ((select core.is_member('studio')) and user_id = (select auth.uid()));
create policy song_comments_delete on app_studio.song_comments for delete to authenticated
  using ((select core.is_member('studio')) and user_id = (select auth.uid()));

-- A reply must answer a top-level comment on the same song.
create or replace function app_studio.check_comment_parent()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.parent_id is not null and not exists (
    select 1 from app_studio.song_comments p
    where p.id = new.parent_id and p.song_id = new.song_id and p.parent_id is null
  ) then
    raise exception 'a reply must answer a top-level comment on the same song';
  end if;
  return new;
end;
$$;
revoke all on function app_studio.check_comment_parent() from public, anon, authenticated;
drop trigger if exists song_comments_check_parent on app_studio.song_comments;
create trigger song_comments_check_parent
  before insert on app_studio.song_comments
  for each row execute function app_studio.check_comment_parent();

-- Playlists ---------------------------------------------------------------------------------
create table if not exists app_studio.playlists (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists playlists_created_by_idx on app_studio.playlists (created_by);
drop trigger if exists playlists_set_updated_at on app_studio.playlists;
create trigger playlists_set_updated_at
  before update on app_studio.playlists
  for each row execute function app_studio.set_updated_at();
alter table app_studio.playlists enable row level security;
revoke all on app_studio.playlists from anon, authenticated;
grant select, delete on app_studio.playlists to authenticated;
grant insert (name), update (name) on app_studio.playlists to authenticated;
drop policy if exists playlists_select on app_studio.playlists;
drop policy if exists playlists_insert on app_studio.playlists;
drop policy if exists playlists_update on app_studio.playlists;
drop policy if exists playlists_delete on app_studio.playlists;
create policy playlists_select on app_studio.playlists for select to authenticated
  using ((select core.is_member('studio')));
create policy playlists_insert on app_studio.playlists for insert to authenticated
  with check ((select core.is_member('studio')) and created_by = (select auth.uid()));
create policy playlists_update on app_studio.playlists for update to authenticated
  using ((select core.is_member('studio')) and created_by = (select auth.uid()))
  with check ((select core.is_member('studio')) and created_by = (select auth.uid()));
create policy playlists_delete on app_studio.playlists for delete to authenticated
  using ((select core.is_member('studio')) and created_by = (select auth.uid()));

create table if not exists app_studio.playlist_songs (
  playlist_id uuid not null references app_studio.playlists (id) on delete cascade,
  song_id     uuid not null references app_studio.songs (id) on delete cascade,
  position    integer not null default 0,
  added_at    timestamptz not null default now(),
  primary key (playlist_id, song_id)
);
create index if not exists playlist_songs_song_idx on app_studio.playlist_songs (song_id);
alter table app_studio.playlist_songs enable row level security;
revoke all on app_studio.playlist_songs from anon, authenticated;
grant select, delete on app_studio.playlist_songs to authenticated;
grant insert (playlist_id, song_id, position), update (position) on app_studio.playlist_songs to authenticated;

-- Owner of the playlist? (security invoker: reads playlists under the caller's RLS.)
create or replace function app_studio.owns_playlist(p_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from app_studio.playlists p where p.id = p_id and p.created_by = auth.uid());
$$;
revoke all on function app_studio.owns_playlist(uuid) from public, anon;
grant execute on function app_studio.owns_playlist(uuid) to authenticated;

drop policy if exists playlist_songs_select on app_studio.playlist_songs;
drop policy if exists playlist_songs_insert on app_studio.playlist_songs;
drop policy if exists playlist_songs_update on app_studio.playlist_songs;
drop policy if exists playlist_songs_delete on app_studio.playlist_songs;
create policy playlist_songs_select on app_studio.playlist_songs for select to authenticated
  using ((select core.is_member('studio')));
create policy playlist_songs_insert on app_studio.playlist_songs for insert to authenticated
  with check ((select core.is_member('studio')) and app_studio.owns_playlist(playlist_id));
create policy playlist_songs_update on app_studio.playlist_songs for update to authenticated
  using ((select core.is_member('studio')) and app_studio.owns_playlist(playlist_id))
  with check ((select core.is_member('studio')) and app_studio.owns_playlist(playlist_id));
create policy playlist_songs_delete on app_studio.playlist_songs for delete to authenticated
  using ((select core.is_member('studio')) and app_studio.owns_playlist(playlist_id));

-- Realtime for the new tables (the app streams them).
do $$
declare t text;
begin
  foreach t in array array['song_likes', 'song_comments', 'playlists', 'playlist_songs'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'app_studio' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table app_studio.%I', t);
    end if;
  end loop;
end $$;
-- Deletes over Realtime need the whole old row to match the stream's primary key.
alter table app_studio.song_likes replica identity full;
alter table app_studio.playlist_songs replica identity full;

-- Covers bucket (private; members read, Edge Functions write).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('studio-covers', 'studio-covers', false, 5242880,
          array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'])
  on conflict (id) do nothing;
drop policy if exists studio_covers_select_members on storage.objects;
create policy studio_covers_select_members on storage.objects for select to authenticated
  using (bucket_id = 'studio-covers' and (select core.is_member('studio')));

insert into core.migrations (app_id, name) values ('studio', 'studio_0003_player') on conflict do nothing;
notify pgrst, 'reload schema';
