-- Studio: per-member daily AI quota (tio-ai-hub docs/SHARED_DB.md, pattern C: server only).
-- Edge Functions (service role) count and insert rows; RLS on with no policies keeps users out.
-- Safe to re-run.

create table if not exists app_studio.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('lyrics')),
  created_at timestamptz not null default now()
);
create index if not exists ai_usage_user_kind_idx on app_studio.ai_usage (user_id, kind, created_at desc);
alter table app_studio.ai_usage enable row level security;
revoke all on app_studio.ai_usage from anon, authenticated;
grant all on app_studio.ai_usage to service_role;

insert into core.migrations (app_id, name) values ('studio', 'studio_0002_ai_usage') on conflict do nothing;
notify pgrst, 'reload schema';
