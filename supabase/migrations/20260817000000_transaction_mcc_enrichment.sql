alter table public.transactions
  add column if not exists mcc_code text,
  add column if not exists mcc_description text,
  add column if not exists mcc_source text,
  add column if not exists mcc_confidence numeric(4,3),
  add column if not exists mcc_verified_at timestamptz;

alter table public.transactions
  drop constraint if exists transactions_mcc_source_check;
alter table public.transactions
  add constraint transactions_mcc_source_check
  check (
    mcc_source is null or mcc_source in (
      'bank_statement',
      'verified_provider',
      'merchant_registry',
      'inferred',
      'unknown'
    )
  );

alter table public.transactions
  drop constraint if exists transactions_mcc_confidence_check;
alter table public.transactions
  add constraint transactions_mcc_confidence_check
  check (mcc_confidence is null or mcc_confidence between 0 and 1);
