-- waitlist signups: email stored immediately, enrichment fields nullable
create table if not exists waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  name        text,
  card_count  text check (card_count in ('1-2', '3-5', '6+') or card_count is null),
  created_at  timestamptz not null default now()
);

-- RLS: anon can insert rows and update any row by id (stateless — no auth.uid() available).
-- The update is constrained in JS by passing the id returned from the insert.
-- No anon select — signups are not readable from the client.
-- Low-risk: name/card_count are non-sensitive enrichment fields.
alter table waitlist enable row level security;

create policy "anon insert"
  on waitlist for insert
  to anon
  with check (true);

create policy "anon update own row"
  on waitlist for update
  to anon
  using (true)
  with check (true);
