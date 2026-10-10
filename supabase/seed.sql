-- Band allowlist. Replace the placeholder emails with the Google / Apple
-- account emails each member signs in with, then run once in the SQL editor.
insert into public.band_members (email, display_name) values
  ('gino@toolution.net',      'Gino'),
  ('vicky@example.com',       'Vicky'),
  ('dingding@example.com',    'Ding Ding 叮叮')
on conflict (email) do update set display_name = excluded.display_name;
