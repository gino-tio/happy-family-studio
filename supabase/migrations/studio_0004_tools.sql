-- studio_0004_tools: split a song into instruments, sing new lyrics over a song's music, and make a
-- new song from an uploaded one (Gino, 2026-11-18, all recommended answers; MusicGPT does the
-- work). Shared-DB rules as in 0001: everything in app_studio, every policy checks
-- core.is_member('studio') first. Safe to re-run.
--
--   songs.parent_song_id   the song a 換歌詞 song was made from (null otherwise).
--   songs.source           null = made from a prompt; 'swap' = new lyrics over a song's music;
--                          'remix' = made from an uploaded song.
--   song_stems             one split of one song: six tracks (vocals, instrumental, piano, bass,
--                          drums, guitar) as [{kind, path}] in the studio-songs bucket. Written
--                          only by the studio-song-tools Edge Function (service role).
--   studio-uploads         private bucket: a member uploads a song into their own folder
--                          ({user id}/...) and only they can read it back; Edge Functions read
--                          it with the service role.

alter table app_studio.songs add column if not exists parent_song_id uuid
  references app_studio.songs (id) on delete set null;
alter table app_studio.songs add column if not exists source text;
alter table app_studio.songs drop constraint if exists songs_source_check;
alter table app_studio.songs add constraint songs_source_check
  check (source is null or source in ('swap', 'remix'));

alter table app_studio.ai_usage drop constraint if exists ai_usage_kind_check;
alter table app_studio.ai_usage add constraint ai_usage_kind_check
  check (kind in ('lyrics', 'cover', 'stems', 'swap', 'remix', 'midi'));

create table if not exists app_studio.song_stems (
  id               uuid primary key default gen_random_uuid(),
  song_id          uuid not null references app_studio.songs (id) on delete cascade,
  created_by       uuid not null references auth.users (id) on delete cascade,
  status           text not null default 'generating'
                     check (status in ('generating', 'done', 'failed')),
  provider_task_id text,
  error            text,
  stems            jsonb not null default '[]'::jsonb check (jsonb_typeof(stems) = 'array'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
-- At most one live split per song; a failed one may be retried.
create unique index if not exists song_stems_one_live_idx on app_studio.song_stems (song_id)
  where status <> 'failed';
create index if not exists song_stems_task_idx on app_studio.song_stems (provider_task_id);
drop trigger if exists song_stems_set_updated_at on app_studio.song_stems;
create trigger song_stems_set_updated_at
  before update on app_studio.song_stems
  for each row execute function app_studio.set_updated_at();
alter table app_studio.song_stems enable row level security;
revoke all on app_studio.song_stems from anon, authenticated;
grant select on app_studio.song_stems to authenticated;
grant all on app_studio.song_stems to service_role;
drop policy if exists song_stems_select_members on app_studio.song_stems;
create policy song_stems_select_members on app_studio.song_stems for select to authenticated
  using ((select core.is_member('studio')));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'app_studio' and tablename = 'song_stems'
  ) then
    alter publication supabase_realtime add table app_studio.song_stems;
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('studio-uploads', 'studio-uploads', false, 20971520,
          array['audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac',
                'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/ogg', 'audio/flac', 'audio/x-flac'])
  on conflict (id) do nothing;
drop policy if exists studio_uploads_insert_own on storage.objects;
drop policy if exists studio_uploads_select_own on storage.objects;
drop policy if exists studio_uploads_delete_own on storage.objects;
create policy studio_uploads_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'studio-uploads' and (select core.is_member('studio'))
              and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy studio_uploads_select_own on storage.objects for select to authenticated
  using (bucket_id = 'studio-uploads' and (select core.is_member('studio'))
         and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy studio_uploads_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'studio-uploads' and (select core.is_member('studio'))
         and (storage.foldername(name))[1] = (select auth.uid())::text);

insert into core.migrations (app_id, name) values ('studio', 'studio_0004_tools') on conflict do nothing;
notify pgrst, 'reload schema';
