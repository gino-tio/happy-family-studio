-- studio_0001_init: TIO Studio on the shared Tio Hub DB (project ddzwhmcxeokkwzmhglft).
-- Follows tio-ai-hub docs/SHARED_DB.md: everything lives in schema app_studio, membership is
-- core.app_members (app id 'studio'), every policy checks core.is_member('studio').
-- Songs are inserted and their status/audio set only by the studio-generate-song Edge Function
-- (service role); members read all songs and may only rename or delete their own.
-- Paste into the SQL Editor of the Hub project and Run. Safe to re-run. Then expose app_studio
-- in Project Settings > Data API, and run supabase/seed.sql once the band has signed in.
insert into core.apps (id, name, join_mode) values ('studio', 'TIO Studio', 'invite')
  on conflict (id) do nothing;
create schema if not exists app_studio;
revoke all on schema app_studio from public, anon;
grant usage on schema app_studio to authenticated, service_role;
alter default privileges in schema app_studio grant all on tables to service_role;
alter default privileges in schema app_studio grant all on sequences to service_role;
alter default privileges in schema app_studio grant execute on functions to service_role;
create or replace function app_studio.me()
returns text language sql stable security invoker set search_path = '' as $$
  select core.app_role('studio');
$$;
create or replace function app_studio.join(p_code text default null)
returns text language sql volatile security invoker set search_path = '' as $$
  select core.join_app('studio', p_code);
$$;
create or replace function app_studio.create_invite(p_role text default 'member')
returns text language sql volatile security invoker set search_path = '' as $$
  select core.create_invite('studio', p_role);
$$;
revoke all on function app_studio.me() from public, anon;
revoke all on function app_studio.join(text) from public, anon;
revoke all on function app_studio.create_invite(text) from public, anon;
grant execute on function app_studio.me() to authenticated;
grant execute on function app_studio.join(text) to authenticated;
grant execute on function app_studio.create_invite(text) to authenticated;
create or replace function app_studio.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function app_studio.set_updated_at() from public, anon, authenticated;
create table if not exists app_studio.songs (
  id               uuid primary key default gen_random_uuid(),
  created_by       uuid not null references auth.users (id) on delete cascade,
  title            text not null check (char_length(title) between 1 and 120),
  style            text not null default '' check (char_length(style) <= 1000),
  lyrics           text not null default '' check (char_length(lyrics) <= 6000),
  instrumental     boolean not null default false,
  length_ms        integer check (length_ms between 10000 and 300000),
  provider         text not null,
  model            text not null,
  status           text not null default 'queued'
                     check (status in ('queued', 'generating', 'done', 'failed')),
  error            text,
  audio_path       text,
  provider_song_id text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists songs_created_at_idx on app_studio.songs (created_at desc);
create index if not exists songs_created_by_idx on app_studio.songs (created_by);
drop trigger if exists songs_set_updated_at on app_studio.songs;
create trigger songs_set_updated_at
  before update on app_studio.songs
  for each row execute function app_studio.set_updated_at();
alter table app_studio.songs enable row level security;
revoke all on app_studio.songs from anon, authenticated;
grant select, delete on app_studio.songs to authenticated;
grant update (title, updated_at) on app_studio.songs to authenticated;
drop policy if exists songs_select_members on app_studio.songs;
drop policy if exists songs_update_own on app_studio.songs;
drop policy if exists songs_delete_own on app_studio.songs;
create policy songs_select_members on app_studio.songs for select to authenticated
  using ((select core.is_member('studio')));
create policy songs_update_own on app_studio.songs for update to authenticated
  using ((select core.is_member('studio')) and created_by = (select auth.uid()))
  with check ((select core.is_member('studio')) and created_by = (select auth.uid()));
create policy songs_delete_own on app_studio.songs for delete to authenticated
  using ((select core.is_member('studio')) and created_by = (select auth.uid()));
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'app_studio' and tablename = 'songs'
  ) then
    alter publication supabase_realtime add table app_studio.songs;
  end if;
end $$;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('studio-songs', 'studio-songs', false, 52428800,
          array['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg'])
  on conflict (id) do nothing;
drop policy if exists studio_songs_select_members on storage.objects;
create policy studio_songs_select_members on storage.objects for select to authenticated
  using (bucket_id = 'studio-songs' and (select core.is_member('studio')));
insert into core.migrations (app_id, name) values ('studio', 'studio_0001_init') on conflict do nothing;
notify pgrst, 'reload schema';
