-- Band membership on the shared Tio Hub DB: each person must sign in to the app once first
-- (so they exist in auth.users), then run this in the SQL Editor. Safe to re-run; anyone who
-- has not signed in yet is simply skipped, so run it again after they do.
insert into core.app_members (user_id, app_id, role)
select u.id, 'studio', m.role
from (values
  ('gino@toolution.net', 'owner'),
  ('onbbin@gmail.com',   'member'),
  ('onbbding@gmail.com', 'member')
) as m (email, role)
join auth.users u on lower(u.email) = m.email
on conflict (user_id, app_id) do update set role = excluded.role;

select u.email, a.role
from core.app_members a join auth.users u on u.id = a.user_id
where a.app_id = 'studio';
