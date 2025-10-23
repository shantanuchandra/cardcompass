# 🎨 Sync Flow Visual Diagrams

## 1. High-Level Component Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                              │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐       │
│  │  Dashboard     │  │  Statements    │  │  Cards         │       │
│  │  Screen        │  │  Screen        │  │  Screen        │       │
│  └────────┬───────┘  └────────────────┘  └────────────────┘       │
└───────────┼─────────────────────────────────────────────────────────┘
            │
            │ onClick: Sync Button
            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATION LAYER                              │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  DashboardOperationsService.syncDataFromGmail()            │    │
│  │    • Shows progress dialog                                  │    │
│  │    • Sets up password callback                              │    │
│  │    • Delegates to DataPipelineDebugService                  │    │
│  └────────────────────────┬────────────────────────────────────┘    │
└───────────────────────────┼─────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       CORE SERVICES                                 │
│  ┌──────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Enhanced        │  │ Pdf Password    │  │ Gemini          │  │
│  │ Gmail Service   │  │ Detection       │  │ Transaction     │  │
│  │                 │  │ Service         │  │ Parser          │  │
│  │ • Search Gmail  │  │                 │  │                 │  │
│  │ • Get profile   │  │ • Try DOB       │  │ • Parse stmt    │  │
│  │ • Download PDF  │  │ • Try hints     │  │ • Parse txns    │  │
│  └──────────────────┘  │ • Manual entry  │  │ • Categorize    │  │
│                        └─────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      REPOSITORY LAYER                               │
│  ┌──────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Card            │  │ Statement       │  │ Transaction      │  │
│  │ Repository      │  │ Repository      │  │ Repository       │  │
│  │                 │  │                 │  │                  │  │
│  │ • getUserCards  │  │ • createStmt    │  │ • addTransaction │  │
│  │ • createCard    │  │ • getStatements │  │ • addBatch       │  │
│  └──────────────────┘  └─────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        DATABASE (Supabase)                          │
│  ┌──────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │  card_catalog   │  │  user_cards     │  │  transactions    │  │
│  │                 │  │                 │  │                  │  │
│  │  • bank         │  │  • user_id      │  │  • user_card_id  │  │
│  │  • card_name    │  │  • catalog_id   │  │  • amount        │  │
│  │  • network      │  │  • last_4_digits│  │  • category      │  │
│  └──────────────────┘  └─────────────────┘  │  • date          │  │
│                                              └──────────────────┘  │
│  ┌──────────────────┐  ┌─────────────────┐                        │
│  │  statements     │  │  emails         │                        │
│  │                 │  │                 │                        │
│  │  • user_card_id │  │  • email_id     │                        │
│  │  • due_date     │  │  • processed    │                        │
│  │  • total_amount │  │  • statement_id │                        │
│  └──────────────────┘  └─────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow - Single Email Processing

```
📧 EMAIL (Gmail API)
    │
    │ contains
    ▼
📎 PDF ATTACHMENT (Encrypted)
    │
    │ download
    ▼
🔒 LOCKED PDF (Binary)
    │
    │ try passwords (DOB, hints)
    ▼
🔓 UNLOCKED PDF
    │
    │ extract text
    ▼
📄 PDF TEXT (Raw String)
    │
    ├─────────────────┬──────────────────┐
    │                 │                  │
    ▼                 ▼                  ▼
🤖 GEMINI AI    🤖 GEMINI AI       🏦 Bank Detection
STATEMENT INFO  TRANSACTIONS       
    │                 │                  │
    ▼                 ▼                  ▼
📊 METADATA       💳 TX LIST        🗂️ CARD INFO
{                 [                  {
  due_date,        {                   bank: "HDFC",
  total_amt,         date,              card: "Regalia"
  statement_date     merchant,        }
}                    amount,
                     category ← 🎯 CATEGORIZED HERE!
                   }
                 ]
    │                 │                  │
    └─────────────────┴──────────────────┘
                      │
                      ▼
          🔍 CARD MAPPING (card_catalog + user_cards)
                      │
                      ├────────┬──────────┐
                      │        │          │
                      ▼        ▼          ▼
                   💾 DB   💾 DB      💾 DB
                  STMT    TXNs       EMAIL
                  TABLE   TABLE      TABLE
```

---

## 3. Transaction Categorization Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    PDF TEXT EXTRACTION                          │
│  "14/05/2025    NETFLIX MUMBAI           149.00 D"             │
│  "15/05/2025    AMAZON SHOPPING          2,348.00 D"           │
│  "16/05/2025    SHELL PETROL PUNE        1,200.00 D"           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│            GEMINI AI TRANSACTION PARSER                         │
│                                                                 │
│  Prompt: "Analyze these transactions and categorize them..."   │
│                                                                 │
│  AI analyzes:                                                   │
│  • Merchant name patterns                                       │
│  • Known categories (Netflix = entertainment)                   │
│  • Keywords (petrol = fuel, amazon = shopping)                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                 GEMINI RESPONSE (JSON)                          │
│  [                                                              │
│    {                                                            │
│      "date": "2025-05-14",                                      │
│      "merchant": "NETFLIX",                                     │
│      "amount": -149.00,                                         │
│      "category": "entertainment" ← 🎯 CATEGORY ASSIGNED        │
│    },                                                           │
│    {                                                            │
│      "date": "2025-05-15",                                      │
│      "merchant": "AMAZON",                                      │
│      "amount": -2348.00,                                        │
│      "category": "shopping" ← 🎯 CATEGORY ASSIGNED             │
│    },                                                           │
│    {                                                            │
│      "date": "2025-05-16",                                      │
│      "merchant": "SHELL PETROL",                                │
│      "amount": -1200.00,                                        │
│      "category": "fuel" ← 🎯 CATEGORY ASSIGNED                 │
│    }                                                            │
│  ]                                                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              CATEGORY ENUM MAPPING (Dart)                       │
│                                                                 │
│  final categoryMap = {                                          │
│    'entertainment': TransactionCategory.entertainment,          │
│    'shopping':      TransactionCategory.shopping,               │
│    'fuel':          TransactionCategory.fuel,                   │
│    'dining':        TransactionCategory.food,                   │
│    'travel':        TransactionCategory.travel,                 │
│    ...                                                          │
│  };                                                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              TRANSACTION OBJECT CREATION                        │
│                                                                 │
│  Transaction(                                                   │
│    userId: "abc-123",                                           │
│    userCardId: "xyz-789",                                       │
│    amount: -149.00,                                             │
│    description: "NETFLIX MUMBAI",                               │
│    category: TransactionCategory.entertainment, ← ✅ MAPPED    │
│    type: TransactionType.debit,                                 │
│    transactionDate: DateTime.parse("2025-05-14"),               │
│    merchantName: "NETFLIX",                                     │
│  )                                                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              DATABASE STORAGE (PostgreSQL)                      │
│                                                                 │
│  INSERT INTO transactions (                                     │
│    user_id,                                                     │
│    user_card_id,                                                │
│    amount,                                                      │
│    description,                                                 │
│    category,        ← 'entertainment' stored as TEXT            │
│    transaction_type,                                            │
│    transaction_date,                                            │
│    merchant_name                                                │
│  ) VALUES (...)                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Card Mapping Flow

```
┌─────────────────────────────────────────────────────────────────┐
│               STATEMENT PARSING RESULT                          │
│  Bank: "HDFC Bank"                                              │
│  Card Variant: "Regalia Gold Credit Card"                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│               BANK NAME NORMALIZATION                           │
│  "HDFC Bank" → "HDFC Bank" (standardized)                       │
│  "hdfc" → "HDFC Bank"                                           │
│  "HDFC BANK LIMITED" → "HDFC Bank"                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│               CARD NAME NORMALIZATION                           │
│  Input: "Regalia Gold Credit Card"                              │
│  Remove: "Credit Card", bank name                               │
│  Output: "Regalia Gold"                                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          SEARCH EXISTING USER_CARDS                             │
│                                                                 │
│  Query user_cards WHERE user_id = 'abc-123'                    │
│  JOIN card_catalog ON catalog_card_id                           │
│                                                                 │
│  Looking for match:                                             │
│    bank ~ "HDFC Bank" AND card_name ~ "Regalia"                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
           ┌─────────────┴──────────────┐
           │                            │
           ▼                            ▼
    ┌──────────────┐          ┌──────────────────┐
    │   FOUND      │          │   NOT FOUND      │
    │              │          │                  │
    │ Return       │          │ Create new       │
    │ user_card_id │          │ association      │
    └──────┬───────┘          └────────┬─────────┘
           │                           │
           │                           ▼
           │                  ┌─────────────────────────────┐
           │                  │ Find/Create in card_catalog │
           │                  │                             │
           │                  │ RPC: create_or_get_card()   │
           │                  │   Input:                    │
           │                  │     bank: "HDFC Bank"       │
           │                  │     card_name: "Regalia"    │
           │                  │   Returns: catalog_card_id  │
           │                  └──────────┬──────────────────┘
           │                             │
           │                             ▼
           │                  ┌─────────────────────────────┐
           │                  │ Create user_cards entry     │
           │                  │                             │
           │                  │ RPC: associate_user_card()  │
           │                  │   Input:                    │
           │                  │     user_id                 │
           │                  │     catalog_card_id         │
           │                  │   Returns: user_card_id     │
           │                  └──────────┬──────────────────┘
           │                             │
           └─────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  FINAL RESULT                                   │
│                                                                 │
│  CardInfo {                                                     │
│    catalogCardId: "catalog-123",    ← for reference            │
│    userCardId: "user-card-456"      ← used in transactions     │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Database Relationships Diagram

```
┌─────────────────────┐
│      users          │
│ ─────────────────── │
│ • id (PK)          │
│ • email            │
│ • full_name        │
└──────┬──────────────┘
       │ 1
       │
       │ has many
       │
       ▼ ∞
┌─────────────────────┐        ┌─────────────────────┐
│    user_cards       │        │   card_catalog      │
│ ─────────────────── │        │ ─────────────────── │
│ • id (PK)          │←──┐    │ • id (PK)          │
│ • user_id (FK)     │   └────│ • bank             │
│ • catalog_card_id  │───────→│ • card_name        │
│   (FK)             │        │ • network          │
│ • last_four_digits │        │ • card_type        │
│ • credit_limit     │        │ • annual_fee       │
└──────┬──────────────┘        └─────────────────────┘
       │ 1
       │
       │ has many
       │
       ▼ ∞
┌─────────────────────┐        ┌─────────────────────┐
│   transactions      │        │    statements       │
│ ─────────────────── │        │ ─────────────────── │
│ • id (PK)          │        │ • id (PK)          │
│ • user_id (FK)     │        │ • user_id (FK)     │
│ • user_card_id (FK)│←───────│ • user_card_id (FK)│
│ • amount           │        │ • statement_date   │
│ • description      │        │ • due_date         │
│ • category ← 🎯   │        │ • total_amount     │
│ • transaction_date │        │ • processed        │
│ • merchant_name    │        └─────────────────────┘
└─────────────────────┘

Legend:
─────→ Foreign Key Reference
∞      One-to-Many Relationship
🎯     Categorization Field
```

---

## 6. Password Detection Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              ENCRYPTED PDF RECEIVED                             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          STEP 1: FETCH USER DOB (if not cached)                 │
│  • Query Google People API                                      │
│  • Parse birthday: 1995-12-02                                   │
│  • Generate formats:                                            │
│    - ddmm: "0212"                                               │
│    - ddmmyyyy: "02121995"                                       │
│    - mmddyyyy: "12021995"                                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          STEP 2: EXTRACT PASSWORD HINTS FROM EMAIL              │
│  • Scan email subject for patterns:                             │
│    - "password is XXXX"                                         │
│    - "use DOB as password"                                      │
│  • Scan email body for hints                                    │
│  • Store potential passwords                                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│          STEP 3: TRY AUTOMATIC PASSWORDS                        │
│  Attempt #1: DOB ddmm       → "0212"       [Try unlock]         │
│  Attempt #2: DOB ddmmyyyy   → "02121995"   [Try unlock]         │
│  Attempt #3: Email hint     → "XXXX"       [Try unlock]         │
│  Attempt #4: Learned pwd    → from cache   [Try unlock]         │
└────────────────────────┬────────────────────────────────────────┘
                         │
           ┌─────────────┴──────────────┐
           │                            │
           ▼ Success                    ▼ All Failed
    ┌──────────────┐          ┌──────────────────┐
    │   UNLOCKED   │          │   MANUAL ENTRY   │
    │              │          │   REQUIRED       │
    │ • Extract    │          │                  │
    │   text       │          │ Trigger callback:│
    │ • Store pwd  │          │ onManualPassword │
    │   for future │          │                  │
    └──────┬───────┘          └────────┬─────────┘
           │                           │
           │                           ▼
           │                  ┌─────────────────┐
           │                  │ Show password   │
           │                  │ input dialog    │
           │                  │ to user         │
           │                  └────────┬────────┘
           │                           │
           │                           ▼
           │                  ┌─────────────────┐
           │                  │ User enters     │
           │                  │ password        │
           │                  └────────┬────────┘
           │                           │
           │                           ▼
           │                  ┌─────────────────┐
           │                  │ Try unlock      │
           │                  │ with manual pwd │
           │                  └────────┬────────┘
           │                           │
           └───────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  PDF TEXT EXTRACTED                             │
│  Ready for Gemini AI parsing                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Error Handling Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              ANY STEP IN SYNC FLOW                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
                   ┌──────────┐
                   │ try {    │
                   │   ...    │
                   └────┬─────┘
                        │
           ┌────────────┴─────────────┐
           │                          │
           ▼ Success                  ▼ Error
    ┌──────────────┐         ┌───────────────────┐
    │  Continue    │         │ catch (error) {   │
    │  Processing  │         │   Log error       │
    └──────┬───────┘         │   Skip or retry   │
           │                 │ }                 │
           │                 └─────┬─────────────┘
           │                       │
           │                       ▼
           │              ┌─────────────────────┐
           │              │ Error Categorization│
           │              │                     │
           │              │ • Recoverable?      │
           │              │ • Skip email?       │
           │              │ • Abort sync?       │
           │              └──────┬──────────────┘
           │                     │
           │        ┌────────────┴────────────┐
           │        │                         │
           │        ▼ Recoverable            ▼ Fatal
           │   ┌──────────┐            ┌──────────┐
           │   │ Log &    │            │ Abort    │
           │   │ Continue │            │ Sync     │
           │   └────┬─────┘            └────┬─────┘
           │        │                       │
           └────────┴───────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              FINAL REPORT WITH ERRORS                           │
│  • Total processed                                              │
│  • Successful                                                   │
│  • Failed with reasons                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Debugging Integration Points

```
Entry Point              Debug Step Name        Key Data Logged
────────────────────────────────────────────────────────────────
🖱️  User clicks          SYNC_STARTED          • numberOfEmails
   sync button                                 • startDate
                                              • userId

🔐 Gmail auth            GMAIL_AUTH            • Success status
                                              • Scopes granted

🔍 Search emails         GMAIL_SEARCH          • Date range
                        EMAIL_FOUND           • Email count

📄 Process each          EMAIL_PROCESSED       • Email index
   email                                       • Bank name
                                              • PDF size

🔓 Unlock PDF            PDF_LOCKED            • Attempt count
                        PDF_UNLOCKED          • Method used
                                              • Text length

🤖 Gemini parse          GEMINI_PARSE          • Text length
   statement            STATEMENT_INFO        • Due date
                                              • Total amount

🤖 Gemini parse          TRANSACTION_PARSE     • TX count
   transactions                               • Categories

🗂️  Map to card          CARD_MAPPING          • Bank name
                                              • Card variant
                                              • Catalog ID
                                              • User card ID

💾 Store to DB           DB_STORED             • Statement ID
                        TRANSACTION_STORED    • TX count

⚠️  Validation           VALIDATION_FAIL       • Reason
                        SKIP_EMAIL            • Bank

✅ Complete              Report generated      • All metrics
```

---

These visual diagrams should help you understand:
1. ✅ How components interact
2. ✅ Where data transforms
3. ✅ When categorization happens
4. ✅ How card mapping works
5. ✅ Database relationships
6. ✅ Password detection flow
7. ✅ Error handling strategy
8. ✅ Where to add debug calls
