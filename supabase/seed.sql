-- Band allowlist — the Google account emails each member signs in with.
-- Already applied to the live project; re-run safely (upsert).
insert into public.band_members (email, display_name) values
  ('gino@toolution.net', 'Gino'),
  ('onbbin@gmail.com',   'Vicky'),
  ('onbbding@gmail.com', 'Ding Ding 叮叮')
on conflict (email) do update set display_name = excluded.display_name;
