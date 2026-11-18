-- studio_0005_sheets: 出譜 (Gino, 2026-11-18, all recommended answers). A pitched track of a split
-- (vocals, piano, bass, guitar) becomes MIDI through MusicGPT Audio to MIDI; the app's sheet page
-- (web/sheet/) draws it as staff, guitar tab or bass tab. Drums need no MIDI from MusicGPT: the
-- sheet page finds kick / snare / hi-hat in the drum track itself. Safe to re-run.
--
--   stem_midis   one MIDI per song and track kind, written only by studio-song-tools (service
--                role); members read. The file sits in studio-songs at <user>/stems/<song>/<kind>.mid.

create table if not exists app_studio.stem_midis (
  id               uuid primary key default gen_random_uuid(),
  song_id          uuid not null references app_studio.songs (id) on delete cascade,
  kind             text not null check (kind in ('vocals', 'piano', 'bass', 'guitar')),
  created_by       uuid not null references auth.users (id) on delete cascade,
  status           text not null default 'generating'
                     check (status in ('generating', 'done', 'failed')),
  provider_task_id text,
  error            text,
  midi_path        text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists stem_midis_one_live_idx on app_studio.stem_midis (song_id, kind)
  where status <> 'failed';
create index if not exists stem_midis_task_idx on app_studio.stem_midis (provider_task_id);
drop trigger if exists stem_midis_set_updated_at on app_studio.stem_midis;
create trigger stem_midis_set_updated_at
  before update on app_studio.stem_midis
  for each row execute function app_studio.set_updated_at();
alter table app_studio.stem_midis enable row level security;
revoke all on app_studio.stem_midis from anon, authenticated;
grant select on app_studio.stem_midis to authenticated;
grant all on app_studio.stem_midis to service_role;
drop policy if exists stem_midis_select_members on app_studio.stem_midis;
create policy stem_midis_select_members on app_studio.stem_midis for select to authenticated
  using ((select core.is_member('studio')));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'app_studio' and tablename = 'stem_midis'
  ) then
    alter publication supabase_realtime add table app_studio.stem_midis;
  end if;
end $$;

-- MIDI files live next to the tracks.
update storage.buckets
  set allowed_mime_types = array['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/ogg',
                                 'audio/midi', 'audio/x-midi']
  where id = 'studio-songs';

insert into core.migrations (app_id, name) values ('studio', 'studio_0005_sheets') on conflict do nothing;
notify pgrst, 'reload schema';
