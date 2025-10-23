# 🔍 Sync Button Data Flow - Complete Debugging Guide

## Overview
This document traces the complete data flow from when the user clicks the sync button to when transactions are categorized and saved in the database.

---

## 📊 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER CLICKS SYNC BUTTON                          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 1: Entry Points                                               │
│  ├─ DashboardScreen._handleSyncData()                              │
│  │  └─ shows sync config dialog (# emails, start date)             │
│  └─ DashboardOperationsService.syncDataFromGmail()                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 2: Show Progress Dialog & Setup Password Callback            │
│  ├─ Display SyncProgressDialog                                     │
│  └─ Configure PasswordInputService callback                        │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 3: Initialize Core Services                                  │
│  ├─ DataPipelineDebugService.debugSequentialUserFlow()            │
│  ├─ Initialize EnhancedGmailService                                │
│  └─ Setup repositories (CardRepo, TransactionRepo, StatementRepo)  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 4: Gmail API - Fetch User Profile & DOB                      │
│  ├─ EnhancedGmailService.getUserProfile()                          │
│  ├─ Calls Google People API for birthday                           │
│  └─ Stores DOB in formats: raw, ddmm, ddmmyyyy                     │
│     (Used for password generation later)                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 5: Gmail API - Search for Statement Emails                   │
│  ├─ EnhancedGmailService.processStatementEmails()                  │
│  ├─ Search query: "has:attachment filename:pdf"                    │
│  ├─ Subject filters: credit card statement, card statement          │
│  ├─ Date range: customStartDate to now                             │
│  └─ Returns: List<StatementParsingResult>                          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 6: Process Each Email Sequentially                           │
│  └─ For each statement in allStatements:                           │
│     ├─ Extract email details (sender, subject, date)               │
│     ├─ Download PDF attachment                                     │
│     └─ Call _processEmailSequentially()                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 7: PDF Password Detection & Unlocking                        │
│  ├─ PdfPasswordDetectionService.findPasswordAndExtractText()       │
│  ├─ Try automatic passwords (DOB-based, email hints)               │
│  ├─ If fails: trigger manual password callback                     │
│  └─ Returns: extracted PDF text                                    │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 8: Gemini AI - Parse Statement Info                          │
│  ├─ GeminiTransactionParser.parseStatementInfo()                   │
│  ├─ Extract: statement_date, due_date, total_amount                │
│  │           minimum_payment, credit_limit, rewards                │
│  └─ Returns: Map<String, dynamic> with statement metadata          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 9: Gemini AI - Parse Transactions                            │
│  ├─ GeminiTransactionParser.parseTransactions()                    │
│  ├─ Extract from PDF: date, description, amount, merchant          │
│  ├─ 🎯 CATEGORIZATION: Gemini assigns category during parsing:    │
│  │   - shopping, dining, travel, fuel, entertainment               │
│  │   - bills, transfer, fee, payment, cash, other                  │
│  └─ Returns: List<Map<String, dynamic>> with categorized txs       │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 10: Validation & Storage Decision                            │
│  ├─ Check: transactions.length > 0                                 │
│  ├─ If YES: proceed to database storage                            │
│  └─ If NO: skip this statement                                     │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 11: Card Catalog Mapping                                     │
│  ├─ _ensureCreditCardExistsWithUserCard()                          │
│  ├─ Look for existing user_card with matching:                     │
│  │   - Bank name (normalized)                                      │
│  │   - Card variant name (from statement)                          │
│  ├─ If NOT FOUND:                                                  │
│  │   ├─ Find/create card_catalog entry                             │
│  │   │   └─ RPC: create_or_get_card_catalog()                      │
│  │   └─ Create user_cards association                              │
│  │       └─ RPC: associate_user_with_card()                        │
│  └─ Returns: CardInfo{catalogCardId, userCardId}                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 12: Store Statement to Database                              │
│  └─ _storeStatementToDatabase()                                    │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ├──────────────────────────────────┐
                             │                                  │
                             ▼                                  ▼
┌──────────────────────────────────────────┐  ┌────────────────────────────────────┐
│  12a: Store Email Record                 │  │  12b: Store Statement Record       │
│  ├─ Table: emails                        │  │  ├─ Table: statements              │
│  ├─ Fields: email_id, subject,          │  │  ├─ Fields: user_card_id,          │
│  │           sender, received_date       │  │  │   statement_date, due_date,     │
│  └─ Check for duplicates                 │  │  │   total_amount, processed       │
└──────────────────┬───────────────────────┘  │  └─ Links to user_cards            │
                   │                           └────────────┬───────────────────────┘
                   │                                        │
                   └────────────────┬───────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 13: Store Transactions with Categorization                   │
│  └─ _storeTransactionsWithDeduplication()                          │
│     ├─ For each transaction:                                       │
│     │   ├─ Map Gemini category to TransactionCategory enum:        │
│     │   │   - shopping → TransactionCategory.shopping              │
│     │   │   - dining → TransactionCategory.food                    │
│     │   │   - travel → TransactionCategory.travel                  │
│     │   │   - fuel → TransactionCategory.fuel                      │
│     │   │   - entertainment → TransactionCategory.entertainment    │
│     │   │   - bills → TransactionCategory.utilities                │
│     │   │   - other → TransactionCategory.general                  │
│     │   └─ Set fields:                                             │
│     │       - userId: from sync userId                             │
│     │       - userCardId: from Step 11 mapping                     │
│     │       - category: mapped TransactionCategory                 │
│     │       - type: debit/credit                                   │
│     │       - amount, date, description, merchantName              │
│     └─ Call: TransactionRepo.addTransactionsBatch()                │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 14: Database RPC Function Call                               │
│  ├─ SupabaseTransactionRepository.addTransaction()                 │
│  ├─ RPC: add_transaction()                                         │
│  ├─ Parameters:                                                    │
│  │   - _user_id: UUID                                              │
│  │   - _user_card_id: UUID (mapped from user_cards)               │
│  │   - _amount: DECIMAL                                            │
│  │   - _description: TEXT                                          │
│  │   - _transaction_date: TIMESTAMPTZ                              │
│  │   - _category: TEXT (from TransactionCategory enum)             │
│  │   - _type: TEXT (debit/credit)                                  │
│  │   - _currency: TEXT (default 'INR')                             │
│  │   - _merchant_name: TEXT                                        │
│  │   - _location: TEXT                                             │
│  └─ Inserts into: transactions table                               │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 15: Update Email Status                                      │
│  ├─ EmailRepository.updateEmailStatus()                            │
│  └─ Mark email as processed with statement_id                      │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Step 16: Complete & Show Results                                  │
│  ├─ Close progress dialog                                          │
│  ├─ Show summary: emails processed, stored to DB                   │
│  └─ Refresh UI to display new data                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Database Schema

### Table: card_catalog
```sql
- id: UUID (primary key)
- bank: TEXT
- card_name: TEXT
- network: TEXT (visa, mastercard, etc.)
- card_type: TEXT (credit, debit)
- annual_fee: DECIMAL
- is_discontinued: BOOLEAN
```

### Table: user_cards
```sql
- id: UUID (primary key) ← THIS is userCardId used in transactions
- user_id: UUID (foreign key → users)
- catalog_card_id: UUID (foreign key → card_catalog)
- last_four_digits: TEXT
- credit_limit: DECIMAL
- is_active: BOOLEAN
```

### Table: transactions
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users)
- user_card_id: UUID (foreign key → user_cards) ← Links to specific user card
- amount: DECIMAL
- description: TEXT
- transaction_date: TIMESTAMPTZ
- category: TEXT (enum: food, fuel, shopping, travel, etc.)
- transaction_type: TEXT (debit, credit)
- currency: TEXT
- merchant_name: TEXT
- location: TEXT
```

### Table: statements
```sql
- id: UUID (primary key)
- user_id: UUID (foreign key → users)
- user_card_id: UUID (foreign key → user_cards)
- statement_date: TIMESTAMPTZ
- due_date: TIMESTAMPTZ
- total_amount: DECIMAL
- processed: BOOLEAN
```

---

## 🔧 Key Files Reference

### Entry Points
- `lib/features/dashboard/presentation/screens/dashboard_screen_refactored.dart`
  - `_handleSyncData()` - Initial sync button handler
  
- `lib/features/dashboard/services/dashboard_operations_service.dart`
  - `syncDataFromGmail()` - Main orchestration method

### Core Processing
- `lib/core/services/data_pipeline_debug_service.dart`
  - `debugSequentialUserFlow()` - Main flow controller
  - `_processEmailSequentially()` - Per-email processing
  - `_storeStatementToDatabase()` - Database storage
  - `_ensureCreditCardExistsWithUserCard()` - Card mapping
  - `_storeTransactionsWithDeduplication()` - Transaction storage

### Gmail & PDF Processing
- `lib/core/services/enhanced_gmail_service.dart`
  - `processStatementEmails()` - Email search & extraction
  - `getUserProfile()` - Fetch DOB from Google People API
  
- `lib/core/services/pdf_password_detection_service.dart`
  - `findPasswordAndExtractText()` - Unlock PDFs

### AI Processing
- `lib/core/services/gemini_transaction_parser.dart`
  - `parseStatementInfo()` - Extract statement metadata
  - `parseTransactions()` - Extract & categorize transactions
  - `_getBankSpecificInstructions()` - Bank-specific parsing rules

### Repository Layer
- `lib/core/repositories/supabase_transaction_repository.dart`
  - `addTransaction()` - Single transaction insert
  - `addTransactionsBatch()` - Batch insert with deduplication
  
- `lib/core/repositories/supabase_card_repository.dart`
  - `getUserCards()` - Fetch user's cards
  
- `lib/core/repositories/supabase_statement_repository.dart`
  - `createStatement()` - Insert statement record

---

## 🎯 Transaction Categorization Flow

### How Categories Are Assigned

1. **During Gemini Parsing** (Step 9)
   ```dart
   // In GeminiTransactionParser.parseTransactions()
   // Gemini AI analyzes merchant name and assigns category:
   {
     "description": "NETFLIX MUMBAI",
     "amount": -149.00,
     "category": "entertainment",  // ← Assigned by Gemini
     "type": "debit"
   }
   ```

2. **Category Mapping** (Step 13)
   ```dart
   // In Transaction model conversion:
   final categoryMap = {
     'shopping': TransactionCategory.shopping,
     'dining': TransactionCategory.food,
     'travel': TransactionCategory.travel,
     'fuel': TransactionCategory.fuel,
     'entertainment': TransactionCategory.entertainment,
     'bills': TransactionCategory.utilities,
     'transfer': TransactionCategory.general,
     'fee': TransactionCategory.general,
     'payment': TransactionCategory.general,
     'cash': TransactionCategory.general,
     'other': TransactionCategory.general,
   };
   ```

3. **Database Storage** (Step 14)
   ```dart
   // Stored as TEXT in database:
   await supabase.rpc('add_transaction', {
     '_category': 'entertainment',  // String value
     // ... other fields
   });
   ```

### Supported Categories
- **food** - Restaurants, cafes, food delivery
- **fuel** - Petrol pumps, gas stations
- **shopping** - Retail, e-commerce, stores
- **travel** - Airlines, hotels, bookings
- **entertainment** - Movies, streaming, events
- **utilities** - Bills, recharges, subscriptions
- **general** - Miscellaneous, transfers, fees

---

## 🐛 Debugging Tips

### Enable Verbose Logging
```dart
// In data_pipeline_debug_service.dart
print('📧 Step 2: Found ${allStatements.length} emails');
print('💾 Database storage completed successfully');
print('✅ GEMINI PARSING: Successfully parsed ${transactions.length} transactions');
```

### Check Database State
```sql
-- View recent transactions with card info
SELECT t.*, uc.last_four_digits, cc.bank, cc.card_name
FROM transactions t
JOIN user_cards uc ON t.user_card_id = uc.id
JOIN card_catalog cc ON uc.catalog_card_id = cc.id
WHERE t.user_id = 'YOUR_USER_ID'
ORDER BY t.created_at DESC
LIMIT 10;

-- Check card mappings
SELECT u.email, uc.*, cc.bank, cc.card_name
FROM user_cards uc
JOIN card_catalog cc ON uc.catalog_card_id = cc.id
JOIN users u ON uc.user_id = u.id
WHERE u.id = 'YOUR_USER_ID';
```

### Test Individual Steps
```dart
// Test Gmail search
final statements = await gmailService.processStatementEmails(
  userId: userId,
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);
print('Found ${statements.length} statements');

// Test Gemini parsing
final transactions = await GeminiTransactionParser.parseTransactions(
  pdfText: pdfText,
  bankName: 'HDFC Bank',
);
print('Parsed ${transactions.length} transactions');
```

### Common Issues

1. **No emails found**
   - Check Gmail API authentication
   - Verify date range
   - Check search query filters

2. **PDF unlock fails**
   - Check DOB is correctly fetched
   - Verify password generation logic
   - Test manual password entry

3. **Transactions not categorized**
   - Check Gemini API response
   - Verify category mapping logic
   - Check if Gemini returned valid categories

4. **Card mapping fails**
   - Check if bank name is normalized correctly
   - Verify card_catalog has matching entry
   - Check user_cards association

5. **Duplicate transactions**
   - Check deduplication logic in `addTransactionsBatch`
   - Verify transaction ID generation
   - Check database constraints

---

## 📝 Example Flow with Real Data

```
User clicks sync button (30 emails, last 30 days)
  ↓
Show progress dialog
  ↓
Fetch DOB: 02/12/1995 → formats: {raw: "1995-12-02", ddmm: "0212", ddmmyyyy: "02121995"}
  ↓
Search Gmail: Found 3 statements (HDFC, ICICI, Axis)
  ↓
Process Email 1: HDFC Regalia
  ↓
  Download PDF (2.3MB) → Try password "0212" → SUCCESS
  ↓
  Extract text (15,234 chars)
  ↓
  Gemini Statement Info:
    - statement_date: 2025-05-16
    - due_date: 2025-06-05
    - total_amount: 28,750.00
    - card_name: "HDFC Regalia"
  ↓
  Gemini Transactions: 47 transactions
    Example:
    {
      date: "2025-05-14",
      description: "NETFLIX MUMBAI",
      amount: -149.00,
      category: "entertainment",
      type: "debit"
    }
  ↓
  Check validation: 47 > 0 ✅
  ↓
  Card mapping:
    - Find catalog: HDFC Bank + Regalia → catalog_id: abc-123
    - Find user_card: user_id + catalog_id → user_card_id: xyz-789
  ↓
  Store statement: statement_id: stmt-456
  ↓
  Store 47 transactions:
    - transaction_id: tx-001, user_card_id: xyz-789, category: entertainment
    - transaction_id: tx-002, user_card_id: xyz-789, category: shopping
    - ... (45 more)
  ↓
  Update email status: processed=true, statement_id=stmt-456
  ↓
✅ Email 1 complete

[Repeat for emails 2-3]

Final summary:
  📧 Emails processed: 3
  💾 Emails stored to DB: 3
  🎉 Total transactions: 142
```

---

## 🚀 Performance Considerations

- **Sequential Processing**: Emails are processed one at a time to avoid rate limits
- **Deduplication**: Transactions checked for duplicates before insertion
- **Batch Insert**: Multiple transactions inserted in batch for efficiency
- **Caching**: Card mappings cached during processing
- **Error Handling**: Continue processing remaining emails if one fails

---

## 📚 Additional Resources

- Supabase Database Functions: `database_complete.sql`
- Gmail API Documentation: https://developers.google.com/gmail/api
- Gemini AI Documentation: https://ai.google.dev/docs
- PDF Processing: `syncfusion_flutter_pdf` package
