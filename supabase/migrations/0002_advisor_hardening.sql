-- 0002 — Supabase security-advisor fixes after 0001.
--
-- * set_updated_at: pin search_path (lint 0011).
-- * is_band_member: anon never needs it (no JWT email → always false), so
--   revoke. `authenticated` keeps EXECUTE on purpose: the app calls it as an
--   RPC for the AuthGate, and it only reveals the caller's own membership.
--   The remaining advisor warning (lint 0029) is expected.

alter function public.set_updated_at() set search_path = public;
revoke execute on function public.is_band_member() from public, anon;
grant execute on function public.is_band_member() to authenticated;
