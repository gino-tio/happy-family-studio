-- Shared DB checks, copied from tio-ai-hub supabase/app-template/checks.sql (keep in step). Read only.
-- tool/apply_migrations.sh runs it after every migration; every row returned is a problem.

with app_tables as (
  select n.nspname as schema, c.relname as name, c.relrowsecurity as rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p') and (n.nspname like 'app\_%' or n.nspname = 'core')
)
-- 1. A table in an app schema or core without RLS.
select 'rls off' as problem, schema || '.' || name as object from app_tables where not rls

union all
-- 2. anon can do anything at all on an app or core table.
select 'anon grant', schema || '.' || name from app_tables
where has_table_privilege('anon', format('%I.%I', schema, name), 'select,insert,update,delete')

union all
-- 3. A new table in public: new apps use their own schema. hub_* and bot_* are the old ones.
select 'new table in public', 'public.' || c.relname
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and c.relname not like 'hub\_%' and c.relname not like 'bot\_%'

union all
-- 4. A function in an app schema or core that anon (or everyone) may run.
select 'function open to anon', n.nspname || '.' || p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname like 'app\_%' or n.nspname = 'core')
  and has_function_privilege('anon', p.oid, 'execute')

union all
-- 5. A security definer function without a fixed search_path.
select 'definer without search_path', n.nspname || '.' || p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname like 'app\_%' or n.nspname = 'core') and p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) s where s like 'search_path=%')

union all
-- 6. A policy in app_<id> that does not check membership of that same app.
select 'policy without own member check', schemaname || '.' || tablename || ' / ' || policyname
from pg_policies
where schemaname like 'app\_%'
  and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) not like
      '%core.%(''' || substring(schemaname from 5) || '''%'

union all
-- 7. A storage policy that names an app bucket but not that app's member check.
select 'storage policy without member check', policyname
from pg_policies p
join core.apps a on (coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '')) like '%''' || a.id || '-%'
where p.schemaname = 'storage' and p.tablename = 'objects'
  and (coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '')) not like '%core.%(''' || a.id || '''%'

union all
-- 8. An app schema with no app registered for it, or an app with no schema.
select 'schema without app', n.nspname from pg_namespace n
where n.nspname like 'app\_%' and not exists (select 1 from core.apps a where 'app_' || a.id = n.nspname)
union all
select 'app without schema', a.id from core.apps a
where a.status = 'active' and not exists (select 1 from pg_namespace n where n.nspname = 'app_' || a.id)

order by 1, 2;
