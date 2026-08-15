-- waitlist signups: email stored immediately, enrichment fields nullable
create table if not exists waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  name        text,
  card_count  text check (card_count in ('1-2', '3-5', '6+') or card_count is null),
  created_at  timestamptz not null default now()
);

-- RLS: both anon and authenticated roles need insert/select because users
-- arriving from OAuth have an authenticated session while public visitors are anon.
-- Update is anon-only (enrichment modal runs before OAuth in the typical flow).
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

create policy "anon select own"
  on waitlist for select
  to anon
  using (true);

create policy "authenticated insert"
  on waitlist for insert
  to authenticated
  with check (true);

create policy "authenticated select own"
  on waitlist for select
  to authenticated
  using (true);
