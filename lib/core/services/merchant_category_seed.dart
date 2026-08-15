/// Merchant name (uppercase, normalized) -> one of the 16 spend categories.
/// Seeds `merchant_category_map` (see the migration in this same task).
/// Covers common Indian and UAE merchants — the two markets this app's
/// statement parsing supports (see `card_normalizer_service.dart`'s bank
/// list). Must never contain a key listed in `ambiguous_merchants.dart`
/// (enforced by a test, see Step 1).
const Map<String, String> merchantCategorySeed = {
  // Food delivery / dining — India
  'SWIGGY': 'food',
  'ZOMATO': 'food',
  'DOMINOS': 'food',
  'MCDONALDS': 'food',
  'STARBUCKS': 'food',
  // Food delivery / dining — UAE
  'TALABAT': 'food',
  'DELIVEROO': 'food',

  // Grocery / supermarket — India
  'BIGBASKET': 'grocery',
  'BLINKIT': 'grocery',
  'ZEPTO': 'grocery',
  'DMART': 'grocery',
  'RELIANCE FRESH': 'grocery',
  // Grocery / supermarket — UAE
  'CARREFOUR': 'grocery',
  'LULU': 'grocery',
  'SPINNEYS': 'grocery',
  'WAITROSE': 'grocery',

  // Shopping — India
  'FLIPKART': 'shopping',
  'MYNTRA': 'shopping',
  'AJIO': 'shopping',
  'NYKAA': 'shopping',
  // Shopping — UAE
  'NOON': 'shopping',
  'NAMSHI': 'shopping',
  'SHEIN': 'shopping',

  // Transport — India
  'OLA': 'transport',
  'UBER': 'transport',
  'RAPIDO': 'transport',
  'IRCTC': 'transport',
  // Transport — UAE
  'CAREEM': 'transport',
  'RTA': 'transport',
  'SALIK': 'transport',

  // Fuel — India
  'INDIAN OIL': 'fuel',
  'BHARAT PETROLEUM': 'fuel',
  'HPCL': 'fuel',
  // Fuel — UAE
  'ADNOC': 'fuel',
  'ENOC': 'fuel',
  'EPPCO': 'fuel',

  // Entertainment — both markets
  'NETFLIX': 'entertainment',
  'SPOTIFY': 'entertainment',
  'BOOKMYSHOW': 'entertainment',
  'PVR': 'entertainment',
  'VOX CINEMAS': 'entertainment',
  'REEL CINEMAS': 'entertainment',

  // Travel — both markets
  'MAKEMYTRIP': 'travel',
  'GOIBIBO': 'travel',
  'INDIGO': 'travel',
  'AIR INDIA': 'travel',
  'EMIRATES': 'travel',
  'ETIHAD': 'travel',
  'BOOKING.COM': 'travel',
  'AIRBNB': 'travel',

  // Utilities — both markets
  'DEWA': 'utilities',
  'ETISALAT': 'utilities',
  'DU': 'utilities',
  'AIRTEL': 'utilities',
  'JIO': 'utilities',

  // Medical — both markets
  'APOLLO PHARMACY': 'medical',
  'PHARMEASY': 'medical',
  'LIFE PHARMACY': 'medical',
  'ASTER PHARMACY': 'medical',

  // Education — both markets
  'BYJUS': 'education',
  'UDEMY': 'education',
  'COURSERA': 'education',
};
