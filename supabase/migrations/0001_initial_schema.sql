-- 0001 — Happy Family Studio initial schema.
--
-- Three people use this app. Access is an allowlist (band_members) rather
-- than "any signed-in user": Google sign-in is open to the world, so RLS
-- must check membership, not just auth.uid() IS NOT NULL.

-- ---------------------------------------------------------------------------
-- Band members allowlist. Rows are added by hand (SQL editor / seed), keyed
-- by the Google/Apple account email.
-- ---------------------------------------------------------------------------
create table public.band_members (
  email        text primary key,
  display_name text not null,
  created_at   timestamptz not null default now()
);

alter table public.band_members enable row level security;

-- security definer so policies can call it without granting SELECT on the
-- allowlist itself to every signed-in stranger.
create or replace function public.is_band_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.band_members
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create policy "members read the member list"
  on public.band_members for select
  using (public.is_band_member());

-- ---------------------------------------------------------------------------
-- Songs: one row per generation request. The generate-song Edge Function
-- inserts the row, calls the AI provider in the background and flips
-- status queued → generating → done | failed. The app watches the table
-- over Realtime.
-- ---------------------------------------------------------------------------
create type public.song_status as enum ('queued', 'generating', 'done', 'failed');

create table public.songs (
  id                uuid primary key default gen_random_uuid(),
  created_by        uuid not null references auth.users (id) on delete cascade,
  title             text not null check (char_length(title) between 1 and 120),
  style             text not null default '' check (char_length(style) <= 1000),
  lyrics            text not null default '' check (char_length(lyrics) <= 6000),
  instrumental      boolean not null default false,
  length_ms         integer check (length_ms between 10000 and 300000),
  provider          text not null,
  model             text not null,
  status            public.song_status not null default 'queued',
  error             text,
  audio_path        text,           -- object path in the private `songs` bucket
  provider_song_id  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index songs_created_at_idx on public.songs (created_at desc);

-- Generic updated_at trigger (tio-help pitfall #9: don't fold this into a
-- column-scoped trigger).
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger songs_set_updated_at
  before update on public.songs
  for each row execute function public.set_updated_at();

alter table public.songs enable row level security;

create policy "members read all songs"
  on public.songs for select
  using (public.is_band_member());

-- Inserts and status updates come from the Edge Function (service role),
-- so members only get to rename / delete their own rows.
create policy "members rename own songs"
  on public.songs for update
  using (public.is_band_member() and created_by = auth.uid())
  with check (public.is_band_member() and created_by = auth.uid());

create policy "members delete own songs"
  on public.songs for delete
  using (public.is_band_member() and created_by = auth.uid());

alter publication supabase_realtime add table public.songs;

-- ---------------------------------------------------------------------------
-- Private audio bucket; reads go through signed URLs.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('songs', 'songs', false)
on conflict (id) do nothing;

create policy "members read song audio"
  on storage.objects for select
  using (bucket_id = 'songs' and public.is_band_member());
