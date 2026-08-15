-- supabase/migrations/20260816000000_merchant_category_map.sql
--
-- Maps a normalized merchant name to one of the 16 transaction spend
-- categories. Seed-only: this table is populated once here and never
-- written to at runtime by the app. An earlier design had a write-back
-- path for a keyword-fallback categorizer tier, but that would have
-- persisted a user's private, unfiltered statement merchant string into
-- a table every authenticated user can read — removed for that reason
-- (design spec §1/§3). Correcting a wrong row is a direct migration edit,
-- same mechanism as adding one.
create table if not exists public.merchant_category_map (
  merchant_name_normalized text primary key,
  category text not null check (category in (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other'
  )),
  created_at timestamptz not null default now()
);

alter table public.merchant_category_map enable row level security;

create policy "merchant_category_map_select_authenticated"
  on public.merchant_category_map
  for select
  to authenticated
  using (true);

grant select on public.merchant_category_map to authenticated;

-- Seed data — must match lib/core/services/merchant_category_seed.dart
-- row for row (verified by test/core/services/merchant_category_seed_test.dart
-- on the Dart side; there is no automated check that this SQL block and
-- the Dart map stay in sync — if you change one, change the other).
insert into public.merchant_category_map (merchant_name_normalized, category) values
  ('SWIGGY', 'food'),
  ('ZOMATO', 'food'),
  ('DOMINOS', 'food'),
  ('MCDONALDS', 'food'),
  ('STARBUCKS', 'food'),
  ('TALABAT', 'food'),
  ('DELIVEROO', 'food'),
  ('BIGBASKET', 'grocery'),
  ('BLINKIT', 'grocery'),
  ('ZEPTO', 'grocery'),
  ('DMART', 'grocery'),
  ('RELIANCE FRESH', 'grocery'),
  ('CARREFOUR', 'grocery'),
  ('LULU', 'grocery'),
  ('SPINNEYS', 'grocery'),
  ('WAITROSE', 'grocery'),
  ('FLIPKART', 'shopping'),
  ('MYNTRA', 'shopping'),
  ('AJIO', 'shopping'),
  ('NYKAA', 'shopping'),
  ('NOON', 'shopping'),
  ('NAMSHI', 'shopping'),
  ('SHEIN', 'shopping'),
  ('OLA', 'transport'),
  ('UBER', 'transport'),
  ('RAPIDO', 'transport'),
  ('IRCTC', 'transport'),
  ('CAREEM', 'transport'),
  ('RTA', 'transport'),
  ('SALIK', 'transport'),
  ('INDIAN OIL', 'fuel'),
  ('BHARAT PETROLEUM', 'fuel'),
  ('HPCL', 'fuel'),
  ('ADNOC', 'fuel'),
  ('ENOC', 'fuel'),
  ('EPPCO', 'fuel'),
  ('NETFLIX', 'entertainment'),
  ('SPOTIFY', 'entertainment'),
  ('BOOKMYSHOW', 'entertainment'),
  ('PVR', 'entertainment'),
  ('VOX CINEMAS', 'entertainment'),
  ('REEL CINEMAS', 'entertainment'),
  ('MAKEMYTRIP', 'travel'),
  ('GOIBIBO', 'travel'),
  ('INDIGO', 'travel'),
  ('AIR INDIA', 'travel'),
  ('EMIRATES', 'travel'),
  ('ETIHAD', 'travel'),
  ('BOOKING.COM', 'travel'),
  ('AIRBNB', 'travel'),
  ('DEWA', 'utilities'),
  ('ETISALAT', 'utilities'),
  ('DU', 'utilities'),
  ('AIRTEL', 'utilities'),
  ('JIO', 'utilities'),
  ('APOLLO PHARMACY', 'medical'),
  ('PHARMEASY', 'medical'),
  ('LIFE PHARMACY', 'medical'),
  ('ASTER PHARMACY', 'medical'),
  ('BYJUS', 'education'),
  ('UDEMY', 'education'),
  ('COURSERA', 'education')
on conflict (merchant_name_normalized) do nothing;
