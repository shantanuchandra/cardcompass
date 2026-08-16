UPDATE public.card_catalog
SET network = CASE
      WHEN network IS NULL OR lower(trim(network)) IN ('', 'unknown')
        THEN 'American Express'
      ELSE network
    END,
    card_url = 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card-with-unlimited-benefits',
    updated_at = now()
WHERE lower(trim(bank)) = 'axis bank'
  AND lower(trim(card_name)) = 'privilege';
