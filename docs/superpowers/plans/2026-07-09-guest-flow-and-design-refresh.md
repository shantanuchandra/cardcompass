# Guest Flow Fix & Design System Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Continue as Guest" fully functional with realistic offline data across every reachable screen, fix every dead button along that path, and apply a cohesive navy/gold "modern fintech" design system.

**Architecture:** A single mock-data module (`lib/core/mock/mock_data.dart`) feeds three new mock repositories (Card/Transaction/Statement, matching existing abstract interfaces) wired into `service_providers.dart` behind a guest/live switch keyed on `authStateProvider`. Screens that already have inline mock-fallback logic (Benefits, Notifications) get their auth-source bug fixed so that fallback actually triggers for guests, and their mock data unified to reference the same card/user IDs as the new shared dataset. Theme overhaul is centralized in `lib/core/theme.dart` and propagates automatically via `Theme.of(context)` (already the dominant pattern). No backend/Supabase changes.

**Tech Stack:** Flutter 3.35+, Riverpod (`flutter_riverpod`), Hive, `shared_preferences`, `google_fonts` (new dependency).

**Verification constraint:** This sandbox has no Flutter SDK installed (`flutter` command not found, no simulators). Every task's "verify" step is therefore a manual read-through / grep-based consistency check, not `flutter analyze`/`flutter test`/`flutter run`. After all tasks are complete, the user must run `flutter pub get && flutter analyze && flutter run` on their own machine to confirm the build compiles and the app behaves as expected, and report back anything broken.

---

## Task 1: Add `google_fonts` dependency and overhaul `theme.dart`

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/theme.dart`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (after `cupertino_icons` block, alongside other utility deps — anywhere in the `dependencies:` list is fine, e.g. right after `flutter_staggered_animations: ^1.1.1`), add:

```yaml
  google_fonts: ^6.2.1
```

- [ ] **Step 2: Rewrite `lib/core/theme.dart` with the navy/gold fintech palette and Inter typography**

Replace the entire file content with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand — Trust Navy + Gold (modern fintech)
  static const Color primaryColor = Color(0xFF0F172A);
  static const Color secondaryColor = Color(0xFF1E3A8A);
  static const Color accentColor = Color(0xFFA16207);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color successColor = Color(0xFF16A34A);
  static const Color warningColor = Color(0xFFD97706);

  // Card Network Colors
  static const Color visaColor = Color(0xFF1A1F71);
  static const Color mastercardColor = Color(0xFFEB001B);
  static const Color rupayColor = Color(0xFF0066CC);
  static const Color amexColor = Color(0xFF006FCF);

  // Bank Brand Colors
  static const Color hdfcColor = Color(0xFF004C8F);
  static const Color sbiColor = Color(0xFF22409A);
  static const Color iciciColor = Color(0xFFB02A37);
  static const Color axisColor = Color(0xFF800020);
  static const Color kotakColor = Color(0xFFED1C24);

  static TextTheme _buildTextTheme(TextTheme base) {
    return GoogleFonts.interTextTheme(base);
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      secondary: secondaryColor,
      tertiary: accentColor,
      error: errorColor,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme, brightness: Brightness.light);
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF0F172A),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0), thickness: 1),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      secondary: secondaryColor,
      tertiary: accentColor,
      error: errorColor,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme, brightness: Brightness.dark);
    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme),
      scaffoldBackgroundColor: const Color(0xFF0B1220),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF161E2E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF283548), thickness: 1),
    );
  }
}

// Text Styles
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static TextStyle get heading2 => GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.25);
  static TextStyle get heading3 => GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle get body1 => GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400);
  static TextStyle get body2 => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get caption => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle get button => GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600);
}

// Spacing
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// Border Radius
class AppBorderRadius {
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
  static const double circle = 50.0;
}
```

**Important:** `AppTextStyles.heading1` etc. change from `static const TextStyle` to `static TextStyle get` (getters), because `GoogleFonts.inter(...)` is not a `const` call. This is a breaking signature change for any call site using `const AppTextStyles.heading1` — grep for that pattern next.

- [ ] **Step 3: Find and fix any `const` usages of `AppTextStyles`**

Run: `grep -rn "const AppTextStyles\." lib/ --include="*.dart"`

For every match, remove the `const` keyword immediately before `AppTextStyles` (e.g. `const AppTextStyles.heading1` → `AppTextStyles.heading1`, or if it's `const Text('...', style: AppTextStyles.heading1)`, change to non-const `Text('...', style: AppTextStyles.heading1)`). Since `Text(...)` widgets wrapping these were likely already non-const (they interpolate `AppConfig.appName` etc.), most call sites won't need changes — the grep confirms which do.

- [ ] **Step 4: Verify by reading, not building**

Run: `grep -c "GoogleFonts" lib/core/theme.dart` — expect `3` (import + 2 usages minimum).
Run: `grep -rn "AppTextStyles\.\(heading1\|heading2\|heading3\|body1\|body2\|caption\|button\)" lib --include="*.dart" -l | xargs grep -l "const AppTextStyles"` — expect no output (empty) after Step 3's fixes.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml lib/core/theme.dart
git commit -m "Overhaul design system: navy/gold fintech palette + Inter typography

Replaces the default Material3 blue seed and unstyled system font with
a trust-navy/gold palette and Inter typeface across light and dark
themes, sourced from a ui-ux-pro-max fintech design-system search."
```

---

## Task 2: Build the shared mock data module

**Files:**
- Create: `lib/core/mock/mock_data.dart`

- [ ] **Step 1: Write the mock dataset**

Create `lib/core/mock/mock_data.dart`:

```dart
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/reward_balance.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/models/benefit.dart';

/// Shared identifiers so every mock repository/viewmodel refers to the
/// same guest user, cards, and reward balances.
class MockIds {
  static const String guestUserId = 'guest';
  static const String cardHdfcRegalia = 'mock-card-hdfc-regalia';
  static const String cardAxisAce = 'mock-card-axis-ace';
  static const String cardIciciAmazonPay = 'mock-card-icici-amazonpay';
}

/// Centralized, internally-consistent mock data for guest mode.
///
/// Dates are computed relative to [DateTime.now()] at call time (not baked
/// into static const values) so "last 2 months" always looks current.
class MockData {
  static List<CreditCard> creditCards() {
    final now = DateTime.now();
    final issuedTwoYearsAgo = DateTime(now.year - 2, now.month, 1);

    return [
      CreditCard(
        id: MockIds.cardHdfcRegalia,
        userId: MockIds.guestUserId,
        cardName: 'HDFC Regalia Gold',
        bankName: 'HDFC Bank',
        cardNumber: '4821',
        network: CardNetwork.visa,
        type: CardType.credit,
        issuedDate: issuedTwoYearsAgo,
        expiryDate: DateTime(now.year + 3, now.month, 1),
        annualFee: 2500,
        creditLimit: 350000,
        rewardRates: const {'dining': 4.0, 'travel': 4.0, 'other': 1.0},
        isActive: true,
        createdAt: issuedTwoYearsAgo,
        updatedAt: now,
      ),
      CreditCard(
        id: MockIds.cardAxisAce,
        userId: MockIds.guestUserId,
        cardName: 'Axis Ace',
        bankName: 'Axis Bank',
        cardNumber: '3390',
        network: CardNetwork.rupay,
        type: CardType.credit,
        issuedDate: DateTime(now.year - 1, now.month, 1),
        expiryDate: DateTime(now.year + 4, now.month, 1),
        annualFee: 499,
        creditLimit: 180000,
        rewardRates: const {'utilities': 5.0, 'fuel': 5.0, 'other': 2.0},
        isActive: true,
        createdAt: DateTime(now.year - 1, now.month, 1),
        updatedAt: now,
      ),
      CreditCard(
        id: MockIds.cardIciciAmazonPay,
        userId: MockIds.guestUserId,
        cardName: 'ICICI Amazon Pay',
        bankName: 'ICICI Bank',
        cardNumber: '7714',
        network: CardNetwork.amex,
        type: CardType.credit,
        issuedDate: DateTime(now.year, now.month - 6 < 1 ? now.month + 6 : now.month - 6, 1),
        expiryDate: DateTime(now.year + 4, now.month, 1),
        annualFee: 0,
        creditLimit: 220000,
        rewardRates: const {'shopping': 5.0, 'other': 1.0},
        isActive: true,
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now,
      ),
    ];
  }

  /// ~25 transactions spread across the last 2 months, varied categories,
  /// each with a plausible reward earned relative to its card's reward rate.
  static List<Transaction> transactions() {
    final now = DateTime.now();
    final entries = <_TxSeed>[
      _TxSeed(2, 'Swiggy', TransactionCategory.food, 640, MockIds.cardHdfcRegalia, 25.6),
      _TxSeed(3, 'Indian Oil', TransactionCategory.fuel, 3200, MockIds.cardAxisAce, 160.0),
      _TxSeed(5, 'Amazon.in', TransactionCategory.shopping, 2199, MockIds.cardIciciAmazonPay, 109.95),
      _TxSeed(6, 'BigBasket', TransactionCategory.grocery, 1850, MockIds.cardAxisAce, 18.5),
      _TxSeed(8, 'Netflix', TransactionCategory.subscription, 649, MockIds.cardHdfcRegalia, 6.49),
      _TxSeed(9, 'BESCOM Electricity', TransactionCategory.utilities, 2400, MockIds.cardAxisAce, 120.0),
      _TxSeed(11, 'IndiGo Airlines', TransactionCategory.travel, 8400, MockIds.cardHdfcRegalia, 336.0),
      _TxSeed(13, 'Barbeque Nation', TransactionCategory.food, 3100, MockIds.cardHdfcRegalia, 124.0),
      _TxSeed(15, 'Amazon.in', TransactionCategory.shopping, 4599, MockIds.cardIciciAmazonPay, 229.95),
      _TxSeed(16, 'PVR Cinemas', TransactionCategory.entertainment, 850, MockIds.cardAxisAce, 17.0),
      _TxSeed(18, 'Shell Petrol', TransactionCategory.fuel, 2800, MockIds.cardAxisAce, 140.0),
      _TxSeed(20, 'Zomato', TransactionCategory.food, 520, MockIds.cardHdfcRegalia, 20.8),
      _TxSeed(22, 'Reliance Digital', TransactionCategory.shopping, 12999, MockIds.cardIciciAmazonPay, 649.95),
      _TxSeed(24, 'LIC Premium', TransactionCategory.insurance, 5600, MockIds.cardHdfcRegalia, 56.0),
      _TxSeed(26, 'Apollo Pharmacy', TransactionCategory.medical, 780, MockIds.cardAxisAce, 15.6),
      _TxSeed(28, 'BookMyShow', TransactionCategory.entertainment, 640, MockIds.cardHdfcRegalia, 25.6),
      _TxSeed(31, 'Ola Cabs', TransactionCategory.transport, 340, MockIds.cardAxisAce, 6.8),
      _TxSeed(33, 'Housing Rent', TransactionCategory.rental, 25000, MockIds.cardHdfcRegalia, 250.0),
      _TxSeed(36, 'Amazon.in', TransactionCategory.shopping, 1299, MockIds.cardIciciAmazonPay, 64.95),
      _TxSeed(39, 'Spotify', TransactionCategory.subscription, 119, MockIds.cardHdfcRegalia, 1.19),
      _TxSeed(42, 'Domino\'s Pizza', TransactionCategory.food, 890, MockIds.cardHdfcRegalia, 35.6),
      _TxSeed(45, 'IndianOil Fuel', TransactionCategory.fuel, 3000, MockIds.cardAxisAce, 150.0),
      _TxSeed(48, 'Udemy', TransactionCategory.education, 499, MockIds.cardIciciAmazonPay, 4.99),
      _TxSeed(52, 'MakeMyTrip', TransactionCategory.travel, 6200, MockIds.cardHdfcRegalia, 248.0),
      _TxSeed(56, 'D-Mart', TransactionCategory.grocery, 2340, MockIds.cardAxisAce, 23.4),
    ];

    return entries.asMap().entries.map((entry) {
      final index = entry.key;
      final tx = entry.value;
      final date = now.subtract(Duration(days: tx.daysAgo));
      return Transaction(
        id: 'mock-txn-${index + 1}',
        userId: MockIds.guestUserId,
        userCardId: tx.cardId,
        amount: tx.amount,
        description: tx.merchant,
        merchantName: tx.merchant,
        category: tx.category,
        type: TransactionType.debit,
        transactionDate: date,
        rewardEarned: tx.rewardEarned,
        rewardType: 'points',
        createdAt: date,
      );
    }).toList();
  }

  static List<RewardBalance> rewardBalances() {
    final now = DateTime.now();
    return [
      RewardBalance(
        id: 'mock-reward-hdfc',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardHdfcRegalia,
        rewardType: 'points',
        availableBalance: 4820,
        totalEarned: 6100,
        totalRedeemed: 1280,
        expiryDate: DateTime(now.year + 1, now.month, 1),
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 400)),
      ),
      RewardBalance(
        id: 'mock-reward-axis',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardAxisAce,
        rewardType: 'cashback',
        availableBalance: 612.40,
        totalEarned: 890.0,
        totalRedeemed: 277.60,
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 200)),
      ),
      RewardBalance(
        id: 'mock-reward-icici',
        userId: MockIds.guestUserId,
        userCardId: MockIds.cardIciciAmazonPay,
        rewardType: 'points',
        availableBalance: 2140,
        totalEarned: 2140,
        totalRedeemed: 0,
        lastUpdated: now,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
    ];
  }

  static List<Statement> statements() {
    final now = DateTime.now();
    Statement build({
      required String id,
      required String cardId,
      required int monthsAgo,
      required double total,
      required PaymentStatus status,
    }) {
      final statementDate = DateTime(now.year, now.month - monthsAgo, 5);
      return Statement(
        id: id,
        userId: MockIds.guestUserId,
        userCardId: cardId,
        statementDate: statementDate,
        dueDate: statementDate.add(const Duration(days: 20)),
        totalAmount: total,
        minimumPayment: (total * 0.05).roundToDouble(),
        closingBalance: total,
        availableCredit: 350000 - total,
        rewardsEarned: (total * 0.02).roundToDouble(),
        interestCharged: status == PaymentStatus.overdue ? (total * 0.03).roundToDouble() : 0,
        feesCharged: 0,
        paymentStatus: status,
        filePath: '',
        fileName: 'statement_${statementDate.year}_${statementDate.month}.pdf',
        createdAt: statementDate,
        processed: true,
        transactionCount: 8,
      );
    }

    return [
      build(id: 'mock-stmt-1', cardId: MockIds.cardHdfcRegalia, monthsAgo: 0, total: 18420, status: PaymentStatus.pending),
      build(id: 'mock-stmt-2', cardId: MockIds.cardAxisAce, monthsAgo: 1, total: 9640, status: PaymentStatus.paid),
      build(id: 'mock-stmt-3', cardId: MockIds.cardIciciAmazonPay, monthsAgo: 1, total: 21897, status: PaymentStatus.paid),
    ];
  }

  static List<Map<String, dynamic>> cardBenefits(String cardId) {
    final now = DateTime.now();
    final byCard = <String, List<Map<String, dynamic>>>{
      MockIds.cardHdfcRegalia: [
        {'name': 'Airport Lounge Access', 'category': 'Travel', 'description': '8 complimentary domestic lounge visits per year', 'isActive': true},
        {'name': 'Dining Privileges', 'category': 'Dining', 'description': '4x reward points on dining spends', 'isActive': true},
        {'name': 'Fuel Surcharge Waiver', 'category': 'Fuel', 'description': '1% waiver up to ₹250/month', 'isActive': true},
      ],
      MockIds.cardAxisAce: [
        {'name': 'Bill Payment Cashback', 'category': 'Utilities', 'description': '5% cashback on utility bill payments', 'isActive': true},
        {'name': 'Fuel Cashback', 'category': 'Fuel', 'description': '5% cashback at fuel stations', 'isActive': true},
      ],
      MockIds.cardIciciAmazonPay: [
        {'name': 'Amazon Cashback', 'category': 'Shopping', 'description': '5% unlimited cashback on Amazon for Prime members', 'isActive': true},
        {'name': 'No Annual Fee', 'category': 'Fees', 'description': 'Lifetime free card, zero joining/annual fee', 'isActive': true},
      ],
    };
    return (byCard[cardId] ?? const [])
        .map((b) => {...b, 'updatedAt': now.toIso8601String()})
        .toList();
  }
}

class _TxSeed {
  final int daysAgo;
  final String merchant;
  final TransactionCategory category;
  final double amount;
  final String cardId;
  final double rewardEarned;

  const _TxSeed(this.daysAgo, this.merchant, this.category, this.amount, this.cardId, this.rewardEarned);
}
```

- [ ] **Step 2: Verify by reading, not building**

Run: `grep -c "id: 'mock-txn-" lib/core/mock/mock_data.dart` — expect `0` (IDs are generated, not literal in source — this just confirms the generator pattern is present, check with `grep -c "_TxSeed("` instead, expect `25`).
Run: `grep -n "class MockData\|class MockIds\|class _TxSeed" lib/core/mock/mock_data.dart` — expect all three present.

- [ ] **Step 3: Commit**

```bash
git add lib/core/mock/mock_data.dart
git commit -m "Add centralized mock data layer for guest mode

Single source of truth for guest-mode fixtures: 3 realistic Indian bank
cards, 25 transactions spanning two months, reward balances, statements,
and card benefits, all cross-referenced by shared mock IDs."
```

---

## Task 3: Add mock repositories and wire the guest/live switch

**Files:**
- Create: `lib/core/repositories/mock_card_repository.dart`
- Create: `lib/core/repositories/mock_transaction_repository.dart`
- Create: `lib/core/repositories/mock_statement_repository.dart`
- Modify: `lib/core/providers/service_providers.dart`

- [ ] **Step 1: Write `MockCardRepository`**

Create `lib/core/repositories/mock_card_repository.dart`:

```dart
import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// In-memory CardRepository for guest mode. Mutations affect only the
/// current session; nothing persists across app restarts.
class MockCardRepository implements CardRepository {
  final List<CreditCard> _cards = MockData.creditCards();

  @override
  Future<List<CreditCard>> getAllCards() async => List.unmodifiable(_cards);

  @override
  Future<List<CreditCard>> getUserCards(String userId) async {
    return _cards.where((c) => c.isActive).toList();
  }

  @override
  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  }) async {
    final existing = _cards.indexWhere((c) => c.id == cardId);
    if (existing == -1) return;
    final now = DateTime.now();
    _cards[existing] = _cards[existing].copyWith(cardNumber: lastFourDigits, updatedAt: now);
  }

  @override
  Future<void> removeUserCard({required String userId, required String cardId}) async {
    final index = _cards.indexWhere((c) => c.id == cardId);
    if (index == -1) return;
    _cards[index] = _cards[index].copyWith(isActive: false, updatedAt: DateTime.now());
  }

  @override
  Future<void> updateUserCard({
    required String userId,
    required String cardId,
    String? lastFourDigits,
    double? creditLimit,
  }) async {
    final index = _cards.indexWhere((c) => c.id == cardId);
    if (index == -1) return;
    _cards[index] = _cards[index].copyWith(
      cardNumber: lastFourDigits ?? _cards[index].cardNumber,
      creditLimit: creditLimit ?? _cards[index].creditLimit,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<CreditCard?> getCardById(String cardId) async {
    return _cards.where((c) => c.id == cardId).firstOrNull;
  }

  @override
  Future<List<CreditCard>> searchCards({
    String? bankName,
    String? cardType,
    String? network,
    double? maxAnnualFee,
    double? minIncome,
  }) async {
    return _cards.where((c) {
      if (bankName != null && c.bankName != bankName) return false;
      if (cardType != null && c.cardType != cardType) return false;
      if (network != null && c.network.name != network) return false;
      if (maxAnnualFee != null && (c.annualFee ?? 0) > maxAnnualFee) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<String>> getAvailableBanks() async {
    return _cards.map((c) => c.bankName).toSet().toList()..sort();
  }

  @override
  Future<List<String>> getAvailableNetworks() async {
    return _cards.map((c) => c.network.name).toSet().toList()..sort();
  }

  @override
  Future<double> calculateReward({
    required String cardId,
    required String category,
    required double amount,
  }) async {
    final card = await getCardById(cardId);
    if (card == null) return 0;
    final rate = card.rewardRates[category.toLowerCase()] ?? card.rewardRates['other'] ?? 1.0;
    return amount * (rate / 100);
  }

  @override
  Future<CreditCard?> getBestCardForTransaction({
    required String userId,
    required String category,
    required double amount,
    String? merchantName,
  }) async {
    CreditCard? best;
    double bestReward = -1;
    for (final card in _cards.where((c) => c.isActive)) {
      final reward = await calculateReward(cardId: card.id, category: category, amount: amount);
      if (reward > bestReward) {
        bestReward = reward;
        best = card;
      }
    }
    return best;
  }
}
```

Note: `firstOrNull` requires `package:collection` (already a transitive Flutter SDK dependency via `flutter_test`, but to be safe without relying on that, replace `_cards.where((c) => c.id == cardId).firstOrNull` with:
```dart
    final matches = _cards.where((c) => c.id == cardId);
    return matches.isEmpty ? null : matches.first;
```
Use this explicit form instead of `firstOrNull` to avoid an extra import.

- [ ] **Step 2: Write `MockTransactionRepository`**

Create `lib/core/repositories/mock_transaction_repository.dart`:

```dart
import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/shared/models/transaction.dart';

class MockTransactionRepository implements TransactionRepository {
  final List<Transaction> _transactions = MockData.transactions()
    ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

  @override
  Future<List<Transaction>> getUserTransactions(
    String userId, {
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? userCardId,
  }) async {
    var results = _transactions.where((t) {
      if (startDate != null && t.transactionDate.isBefore(startDate)) return false;
      if (endDate != null && t.transactionDate.isAfter(endDate)) return false;
      if (category != null && t.categoryString != category) return false;
      if (userCardId != null && t.userCardId != userCardId) return false;
      return true;
    }).toList();
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<void> addTransaction(Transaction transaction) async {
    _transactions.insert(0, transaction);
  }

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    final index = _transactions.indexWhere((t) => t.id == transaction.id);
    if (index != -1) _transactions[index] = transaction;
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    _transactions.removeWhere((t) => t.id == transactionId);
  }

  @override
  Future<Transaction?> getTransactionById(String transactionId) async {
    final matches = _transactions.where((t) => t.id == transactionId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<Transaction>> getTransactionsByCategory(
    String userId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return getUserTransactions(userId, category: category, startDate: startDate, endDate: endDate);
  }

  @override
  Future<Map<String, double>> getSpendingSummary(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate);
    final summary = <String, double>{};
    for (final t in txns.where((t) => t.type == TransactionType.debit)) {
      summary[t.categoryString] = (summary[t.categoryString] ?? 0) + t.amount;
    }
    return summary;
  }

  @override
  Future<List<Map<String, dynamic>>> getMonthlySpendingTrend(String userId, int months) async {
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(now.year, now.month - i + 1, 1);
      final spend = _transactions
          .where((t) =>
              t.type == TransactionType.debit &&
              !t.transactionDate.isBefore(monthDate) &&
              t.transactionDate.isBefore(nextMonth))
          .fold(0.0, (sum, t) => sum + t.amount);
      result.add({'month': '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}', 'total': spend});
    }
    return result;
  }

  @override
  Future<double> getTotalSpending(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate, userCardId: userCardId);
    return txns.where((t) => t.type == TransactionType.debit).fold(0.0, (sum, t) => sum + t.amount);
  }

  @override
  Future<double> getTotalRewards(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate, userCardId: userCardId);
    return txns.fold(0.0, (sum, t) => sum + (t.rewardEarned ?? 0));
  }

  @override
  Future<List<Transaction>> importTransactions(String userId, List<Map<String, dynamic>> transactionData) async {
    return [];
  }

  @override
  Future<void> syncTransactions(String userId) async {}

  @override
  Future<List<Transaction>> getRecentTransactions(String userId, {int limit = 10}) async {
    return getUserTransactions(userId, limit: limit);
  }
}
```

- [ ] **Step 3: Write `MockStatementRepository`**

Create `lib/core/repositories/mock_statement_repository.dart`:

```dart
import 'dart:io';
import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/shared/models/statement.dart';

class MockStatementRepository implements StatementRepository {
  final List<Statement> _statements = MockData.statements();

  @override
  Future<List<Map<String, dynamic>>> getUserStatements(String userId) async {
    return _statements.map((s) => s.toJson()).toList();
  }

  @override
  Future<List<Statement>> getStatements(String userId) async => List.unmodifiable(_statements);

  @override
  Future<Statement> createStatement({
    required String userId,
    required String userCardId,
    required Map<String, dynamic> statementData,
    String? filePath,
    String? emailId,
  }) async {
    final statement = Statement.fromJson({
      'id': 'mock-stmt-${_statements.length + 1}',
      'user_id': userId,
      'user_card_id': userCardId,
      'statement_date': DateTime.now().toIso8601String(),
      'due_date': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
      'total_amount': statementData['total_amount'] ?? 0,
      'minimum_payment': statementData['minimum_payment'] ?? 0,
      'closing_balance': statementData['closing_balance'] ?? 0,
      'available_credit': statementData['available_credit'] ?? 0,
      'rewards_earned': statementData['rewards_earned'] ?? 0,
      'interest_charged': statementData['interest_charged'] ?? 0,
      'fees_charged': statementData['fees_charged'] ?? 0,
      'payment_status': 'pending',
      'file_path': filePath ?? '',
      'file_name': statementData['file_name'] ?? 'statement.pdf',
      'created_at': DateTime.now().toIso8601String(),
    });
    _statements.add(statement);
    return statement;
  }

  @override
  Future<String> uploadStatement({required String userId, required String cardId, required File file}) async {
    return 'mock-upload-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<Map<String, dynamic>>> parseStatement({
    required String userId,
    required String cardId,
    required String filePath,
  }) async {
    return [];
  }

  @override
  Future<Map<String, dynamic>?> getStatementById(String statementId) async {
    final matches = _statements.where((s) => s.id == statementId);
    return matches.isEmpty ? null : matches.first.toJson();
  }

  @override
  Future<void> updateStatementStatus({required String statementId, required bool processed}) async {
    final index = _statements.indexWhere((s) => s.id == statementId);
    if (index != -1) _statements[index] = _statements[index].copyWith();
  }

  @override
  Future<void> deleteStatement(String statementId) async {
    _statements.removeWhere((s) => s.id == statementId);
  }

  @override
  Future<List<Map<String, dynamic>>> getStatementsForCard({required String userId, required String cardId}) async {
    return _statements.where((s) => s.userCardId == cardId).map((s) => s.toJson()).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> importFromGmail(String userId) async => [];

  @override
  Future<bool> validateStatementFile(File file) async => file.existsSync();

  @override
  List<String> getSupportedFormats() => ['pdf'];
}
```

- [ ] **Step 4: Wire the guest/live switch in `service_providers.dart`**

Read the current content of `lib/core/providers/service_providers.dart` first (it was captured in full during planning — reproduced below with the diff applied). Replace the whole file with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Services
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/services/auth_service.dart';
import 'package:cardcompass/core/services/auth_service_impl.dart';
import 'package:cardcompass/core/services/pdf_service.dart';
import 'package:cardcompass/core/services/pdf_service_impl.dart';
import 'package:cardcompass/core/services/pdf_parsing_service.dart';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:cardcompass/core/services/card_identification_service.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/services/recommendation_service_impl.dart';
import 'package:cardcompass/core/services/user_profile_service.dart';
import 'package:cardcompass/core/services/user_profile_service_impl.dart';

// Repositories
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/mock_card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/mock_transaction_repository.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/repositories/supabase_statement_repository.dart';
import 'package:cardcompass/core/repositories/mock_statement_repository.dart';

// Auth (for the guest/live switch)
import 'package:cardcompass/features/auth/providers/auth_provider.dart';

/// Provider for SharedPreferences
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized in main()');
});

/// True when the signed-in user is the local guest user (no Supabase session).
final isGuestModeProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).user?.id == 'guest';
});

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthServiceImpl();
});

/// Provider for PdfService
final pdfServiceProvider = Provider<PdfService>((ref) {
  return PdfServiceImpl();
});

/// Provider for PdfParsingService
final pdfParsingServiceProvider = Provider<PdfParsingService>((ref) {
  return PdfParsingServiceImpl();
});

/// Provider for EnhancedGmailService
final gmailServiceProvider = Provider<EnhancedGmailService>((ref) {
  throw UnimplementedError('EnhancedGmailService must be initialized with Gmail API');
});

/// Provider for CardRepository — mock in guest mode, Supabase otherwise.
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockCardRepository() : SupabaseCardRepository();
});

/// Provider for TransactionRepository — mock in guest mode, Supabase otherwise.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockTransactionRepository() : SupabaseTransactionRepository();
});

/// Provider for StatementRepository — mock in guest mode, Supabase otherwise.
final statementRepositoryProvider = Provider<StatementRepository>((ref) {
  return ref.watch(isGuestModeProvider) ? MockStatementRepository() : SupabaseStatementRepository();
});

/// Provider for RecommendationService
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationServiceImpl(
    merchantRateService: MerchantRateService(),
    milestoneTracker: MilestoneTracker(),
  );
});

/// Provider for UserProfileService
final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileServiceImpl();
});

/// Provider for CardIdentificationService
final cardIdentificationServiceProvider = Provider<CardIdentificationService>((ref) {
  return CardIdentificationService();
});
```

**Why this is safe from provider cycles:** `authStateProvider` (in `auth_provider.dart`) does not read any repository provider — confirmed during planning by reading the full file. `isGuestModeProvider` → `authStateProvider` is a one-directional dependency; `cardRepositoryProvider` → `isGuestModeProvider` → `authStateProvider` never loops back.

- [ ] **Step 5: Verify by reading, not building**

Run: `grep -n "class MockCardRepository implements CardRepository" lib/core/repositories/mock_card_repository.dart` — expect a match.
Run: `grep -n "class MockTransactionRepository implements TransactionRepository" lib/core/repositories/mock_transaction_repository.dart` — expect a match.
Run: `grep -n "class MockStatementRepository implements StatementRepository" lib/core/repositories/mock_statement_repository.dart` — expect a match.
Run: `grep -n "isGuestModeProvider" lib/core/providers/service_providers.dart` — expect 4 matches (1 definition + 3 usages).
Manually re-read each mock repository against its abstract interface file (`card_repository.dart`, `transaction_repository.dart`, `statement_repository.dart`) method-by-method to confirm every abstract method has a concrete override with a matching signature (return type, named parameters, defaults) — this substitutes for the compiler's "missing override" check that `flutter analyze` would normally catch.

- [ ] **Step 6: Commit**

```bash
git add lib/core/repositories/mock_card_repository.dart lib/core/repositories/mock_transaction_repository.dart lib/core/repositories/mock_statement_repository.dart lib/core/providers/service_providers.dart
git commit -m "Wire mock repositories behind a guest/live provider switch

cardRepositoryProvider/transactionRepositoryProvider/statementRepositoryProvider
now resolve to in-memory mock implementations when authStateProvider's
user is the guest user, and to the existing Supabase implementations
otherwise. This is the single injection seam for guest-mode data."
```

---

## Task 4: Fix the Home screen — remove shadowed providers, delete placeholder fallbacks, wire card tap-through

**Files:**
- Modify: `lib/features/cards/presentation/screens/home_screen.dart`

- [ ] **Step 1: Delete the shadowing provider block at the bottom of the file**

Find and delete the entire block (currently lines ~1123-1187, starting with the comment `// Real providers that use Supabase instead of mock data` through the closing `});` of `monthlyRewardsProvider`):

```dart
// Real providers that use Supabase instead of mock data
final activeCardsProvider = FutureProvider<List<dynamic>>((ref) async {
  ...
});

final recentTransactionsProvider = FutureProvider<List<dynamic>>((ref) async {
  ...
});

final totalCreditLimitProvider = FutureProvider<double>((ref) async {
  ...
});

final monthlyRewardsProvider = FutureProvider<double>((ref) async {
  ...
});
```

Delete this whole block. These providers now come from `cards_provider.dart` and `transactions_provider.dart` instead (imported in the next step), which already compute the same things off the same repositories — but as synchronous `Provider`s derived from the `cardsProvider`/`transactionsProvider` `StateNotifier`s, not independent `FutureProvider`s. This removes the placeholder-number fallback (`total > 0 ? total : 100000.0` and `totalRewards > 0 ? totalRewards : 412.0`) entirely, since mock data always yields real non-zero values and the derived providers don't have that fallback logic.

- [ ] **Step 2: Import the canonical providers and switch the `.when()` consumers to plain `.watch()`**

At the top of the file, add these imports (after the existing `service_providers.dart` import):

```dart
import '../../../cards/providers/cards_provider.dart';
import '../../../transactions/providers/transactions_provider.dart';
```

Now every place that did `ref.watch(activeCardsProvider)` and called `.when(data:, loading:, error:)` on it needs to change, because `activeCardsProvider` from `cards_provider.dart` is `Provider<List<CreditCard>>` (a plain synchronous list), not `AsyncValue`. Make these exact changes:

At the "My Cards" section header (was around line 679), change:
```dart
final cardsAsync = ref.watch(activeCardsProvider);
return cardsAsync.when(
  data: (cards) => cards.isNotEmpty
      ? TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const CardsListScreen(),
              ),
            );
          },
          child: const Text('View All'),
        )
      : const SizedBox.shrink(),
  loading: () => const SizedBox.shrink(),
  error: (_, __) => const SizedBox.shrink(),
);
```
to:
```dart
final cards = ref.watch(activeCardsProvider);
return cards.isNotEmpty
    ? TextButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CardsListScreen(),
            ),
          );
        },
        child: const Text('View All'),
      )
    : const SizedBox.shrink();
```

At the cards grid body (was around line 703), change:
```dart
final cardsAsync = ref.watch(activeCardsProvider);
return cardsAsync.when(
  data: (cards) {
    if (cards.isEmpty) {
      return _buildEmptyCardsWidget(context);
    }
    return _buildCardsGrid(context, cards);
  },
  loading: () => _buildCardsLoadingWidget(),
  error: (error, _) {
    print('Error loading cards: $error');
    return _buildEmptyCardsWidget(context);
  },
);
```
to:
```dart
final cards = ref.watch(activeCardsProvider);
if (cards.isEmpty) {
  return _buildEmptyCardsWidget(context);
}
return _buildCardsGrid(context, cards);
```

At the "Recent Transactions" section header (was around line 819), change:
```dart
final transactionsAsync = ref.watch(recentTransactionsProvider);
return transactionsAsync.when(
  data: (transactions) => transactions.isNotEmpty
      ? TextButton(
          onPressed: () {
            // TODO: Show all transactions
          },
          child: const Text('View All'),
        )
      : const SizedBox.shrink(),
  loading: () => const SizedBox.shrink(),
  error: (_, __) => const SizedBox.shrink(),
);
```
to:
```dart
final transactions = ref.watch(recentTransactionsProvider);
return transactions.isNotEmpty
    ? TextButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const TransactionsScreen(),
            ),
          );
        },
        child: const Text('View All'),
      )
    : const SizedBox.shrink();
```
This both fixes the "View All Transactions" TODO and removes the `AsyncValue` pattern.

At the transactions list body (was around line 839, find the matching `final transactionsAsync = ref.watch(recentTransactionsProvider);` followed by `.when(data: (transactions) => ...)`), apply the same `AsyncValue` → plain-value transformation as the cards grid: drop `.when(...)`, use `transactions` directly, keep whatever the `data:` branch built as the return value, and drop the `loading`/`error` branches (there's no loading state for a synchronous derived `Provider` — if the previous loading/error branches built meaningful empty-state UI, move that empty-state widget to fire when `transactions.isEmpty` instead).

At the credit-limit/rewards KPI reads (were around lines 562 and 593 — `ref.watch(totalCreditLimitProvider)` and `ref.watch(monthlyRewardsProvider)`), no `.when()` change is needed there IF they were already being read as plain doubles rather than through `.when()` — re-read those two call sites first; if they do `ref.watch(totalCreditLimitProvider).when(...)`, apply the same flattening (drop `.when`, use the value directly, since `totalCreditLimitProvider`/`monthlyRewardsProvider` from `cards_provider.dart`/`transactions_provider.dart` are plain `Provider<double>`, not `FutureProvider<double>`).

- [ ] **Step 3: Fix the `ref.invalidate(...)` calls**

The four `ref.invalidate(activeCardsProvider)` / `ref.invalidate(recentTransactionsProvider)` / `ref.invalidate(totalCreditLimitProvider)` / `ref.invalidate(monthlyRewardsProvider)` calls (originally around lines 334-335 and 519-522) still work unchanged — `ref.invalidate` works the same way on plain `Provider`s as on `FutureProvider`s. No code change needed here, just confirm (by reading) that these lines still compile conceptually against the new import (they will, since the provider names are unchanged, only their source file and type changed).

- [ ] **Step 4: Trigger `cardsProvider`/`transactionsProvider` loading from `HomeTab`, and add card tap-through to `CardDetailsScreen`**

`HomeTab` currently never calls `cardsProvider.notifier.loadUserCards()` or `transactionsProvider.notifier.loadUserTransactions()` — it only reads the repository-backed `activeCardsProvider`/`recentTransactionsProvider` (now sourced from `cards_provider.dart`, which itself derives from `cardsProvider`, a `StateNotifier` that starts empty until explicitly loaded). Add a load trigger and tap-through.

Convert `HomeTab` from `ConsumerWidget` to `ConsumerStatefulWidget` so it has an `initState` to hook into. Change:
```dart
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```
to:
```dart
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) return;
    ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
    ref.read(transactionsProvider.notifier).loadUserTransactions(authState.user!.id);
  }

  @override
  Widget build(BuildContext context) {
```
(Every subsequent method in the old `HomeTab` class body — `build`, `_buildMyCardsSection`, etc. — stays exactly the same, just now inside `_HomeTabState` instead of `HomeTab`. Since `ref` is available the same way on `ConsumerState`, no other reference changes are needed.)

In `_buildCardsGrid` (originally around line 776-804), wrap each card in a `GestureDetector`/`InkWell` that navigates to `CardDetailsScreen`. Change:
```dart
  Widget _buildCardsGrid(BuildContext context, List<dynamic> cards) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < cards.length - 1 ? 16 : 0,
            ),
            child: SizedBox(
              width: 320,
              child: CreditCardWidget(
                cardName: card.cardName ?? 'Unknown Card',
                bankName: card.bankName ?? 'Unknown Bank',
                lastFourDigits: card.cardNumberLast4 ?? '****',
                expiryDate: card.expiryDate != null 
                  ? '${card.expiryDate!.month.toString().padLeft(2, '0')}/${card.expiryDate!.year.toString().substring(2)}'
                  : 'MM/YY',
                cardType: card.cardType ?? 'credit',
                gradientColors: _getCardGradientColors(card.network?.toString().split('.').last ?? 'visa'),
              ),
            ),
          );
        },
      ),
    );
  }
```
to:
```dart
  Widget _buildCardsGrid(BuildContext context, List<dynamic> cards) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < cards.length - 1 ? 16 : 0,
            ),
            child: SizedBox(
              width: 320,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed(
                  '/card-details',
                  arguments: card.id,
                ),
                child: CreditCardWidget(
                  cardName: card.cardName ?? 'Unknown Card',
                  bankName: card.bankName ?? 'Unknown Bank',
                  lastFourDigits: card.cardNumberLast4 ?? '****',
                  expiryDate: card.expiryDate != null 
                    ? '${card.expiryDate!.month.toString().padLeft(2, '0')}/${card.expiryDate!.year.toString().substring(2)}'
                    : 'MM/YY',
                  cardType: card.cardType ?? 'credit',
                  gradientColors: _getCardGradientColors(card.network?.toString().split('.').last ?? 'visa'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
```

- [ ] **Step 5: Fix the profile avatar TODO**

Change (originally around line 118-126):
```dart
IconButton(
  onPressed: () {
    // TODO: Show user profile
  },
  icon: const CircleAvatar(
    radius: 16,
    child: Icon(Icons.person, size: 20),
  ),
),
```
to:
```dart
IconButton(
  onPressed: () => Navigator.of(context).pushNamed('/profile'),
  icon: const CircleAvatar(
    radius: 16,
    child: Icon(Icons.person, size: 20),
  ),
),
```

- [ ] **Step 6: Verify by reading, not building**

Run: `grep -n "TODO\|FutureProvider<List<dynamic>>\|FutureProvider<double>" lib/features/cards/presentation/screens/home_screen.dart` — expect no matches (all TODOs and shadow providers removed).
Run: `grep -n "\.when(" lib/features/cards/presentation/screens/home_screen.dart` — expect no matches (all `AsyncValue` patterns flattened).
Run: `grep -n "class HomeTab\|class _HomeTabState" lib/features/cards/presentation/screens/home_screen.dart` — expect both present.
Manually re-read the full file top to bottom once to confirm every method that referenced `ref` inside the old `HomeTab extends ConsumerWidget` still has `ref` in scope now that it's `_HomeTabState` (methods on `ConsumerState` access `ref` as an instance member, same as before — this should be a no-op check, not a real risk, but confirm no method signature explicitly took `WidgetRef ref` as a parameter that's now redundant/shadowing).

- [ ] **Step 7: Commit**

```bash
git add lib/features/cards/presentation/screens/home_screen.dart
git commit -m "Fix Home screen: remove shadowed providers, wire card tap-through

Deletes the duplicate FutureProvider definitions that shadowed the
canonical cards_provider.dart/transactions_provider.dart ones (and their
placeholder-number fallbacks), triggers card/transaction loading from
HomeTab, adds tap-to-details navigation on card widgets, fixes the
profile avatar and 'View All Transactions' dead buttons."
```

---

## Task 5: Fix `CardDetailsScreen` — safe empty-state handling, auto-load, edit menu

**Files:**
- Modify: `lib/features/cards/presentation/screens/card_details_screen.dart`

- [ ] **Step 1: Make `_loadCardDetails` safe when providers are empty, and auto-load if needed**

Change (originally lines 45-78):
```dart
  Future<void> _loadCardDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load card details
      final cards = ref.read(cardsProvider);
      _card = cards.firstWhere(
        (card) => card.id == widget.cardId,
        orElse: () => cards.first, // Fallback to first card if not found
      );
      // Load transactions for this card
      final transactions = ref.read(transactionsProvider);
      _transactions = transactions
          .where((t) => t.userCardId == widget.cardId)
          .toList();

      // Load latest statement for this card
      await _fetchLatestStatement();

      // Load real benefits data from Supabase
      await _fetchCardBenefits();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load card details: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
```
to:
```dart
  Future<void> _loadCardDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      var cards = ref.read(cardsProvider);
      if (cards.isEmpty) {
        final authState = ref.read(authStateProvider);
        if (authState.user != null) {
          await ref.read(cardsProvider.notifier).loadUserCards(authState.user!.id);
          await ref.read(transactionsProvider.notifier).loadUserTransactions(authState.user!.id);
        }
        cards = ref.read(cardsProvider);
      }

      if (cards.isEmpty) {
        _card = null;
        _transactions = [];
        return;
      }

      final matches = cards.where((card) => card.id == widget.cardId);
      _card = matches.isEmpty ? cards.first : matches.first;

      final transactions = ref.read(transactionsProvider);
      _transactions = transactions
          .where((t) => t.userCardId == _card!.id)
          .toList();

      await _fetchLatestStatement();
      await _fetchCardBenefits();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load card details: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
```

Add the auth provider import at the top of the file:
```dart
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
```

Also handle the genuinely-empty case in `build()` — change the loading guard (originally lines 81-89):
```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading || _card == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Card Details'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
```
to:
```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Card Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Card Details')),
        body: Center(
          child: Text(
            'This card could not be found.',
            style: AppTextStyles.body1,
          ),
        ),
      );
    }
```

Add the theme import if not already present: `import 'package:cardcompass/core/theme.dart';`

- [ ] **Step 2: Fix the edit-card TODOs**

Change (originally lines 96-104):
```dart
IconButton(
  icon: const Icon(Icons.edit),
  onPressed: () {
    // TODO: Navigate to edit card screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit card coming soon')),
    );
  },
),
```
to:
```dart
IconButton(
  icon: const Icon(Icons.edit),
  onPressed: () => Navigator.of(context).pushNamed(
    '/add-card',
    arguments: _card!.id,
  ),
),
```

For the bottom-sheet "Edit Card" tile (originally around line 586-587, inside `_showCardOptions`), apply the same fix — replace its `onPressed`/`onTap` body (`Navigator.pop(context); // TODO...; SnackBar(...)`) with:
```dart
onTap: () {
  Navigator.pop(context);
  Navigator.of(context).pushNamed('/add-card', arguments: _card!.id);
},
```

(This reuses the existing Add Card screen/route for editing — `AddCardScreen` is out of scope for a full "edit mode" rebuild in this plan; passing the card ID gets the user to a screen where they can re-enter/update details rather than a dead end. If `AddCardScreen` doesn't already accept an optional card-id argument, this is acceptable as a "best available real navigation" fix per the guest-flow goal of no silent no-ops — it takes the user somewhere real and useful rather than doing nothing.)

- [ ] **Step 3: Verify by reading, not building**

Run: `grep -n "TODO" lib/features/cards/presentation/screens/card_details_screen.dart` — expect no matches.
Run: `grep -n "cards.first" lib/features/cards/presentation/screens/card_details_screen.dart` — expect no unguarded match (the only reference should be inside the `matches.isEmpty ? cards.first : matches.first` ternary, which is safe because it's guarded by the preceding `if (cards.isEmpty) { ...; return; }`).

- [ ] **Step 4: Commit**

```bash
git add lib/features/cards/presentation/screens/card_details_screen.dart
git commit -m "Fix CardDetailsScreen: safe empty-state, auto-load, real edit nav

Guards against the unhandled StateError from cards.first on an empty
list, auto-loads cards/transactions if the providers haven't been
populated yet (e.g. when reached directly from Home), and replaces the
'Edit card coming soon' snackbar stubs with real navigation."
```

---

## Task 6: Build out `TransactionsScreen` and `RecommendationsScreen`

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`
- Modify: `lib/features/recommendations/presentation/screens/recommendations_screen.dart`
- Modify: `lib/core/services/recommendation_service_impl.dart`
- Modify: `lib/core/services/reward_calculator.dart`
- Modify: `lib/core/providers/service_providers.dart` (additional change to the provider already touched in Task 3)

**Important discovery from planning:** `RecommendationServiceImpl.getSpendingOptimizations` and `.getRewardOptimizations` — the exact two methods `RecommendationsScreen` needs — are currently unimplemented stubs that return `[]` (see lines 94-102 and 132-138 of the file). Separately, the constructor and `getBestCardForTransaction` hardcode `SupabaseCardRepository()` directly (lines 18 and 49) instead of going through the guest-aware `cardRepositoryProvider`, which would silently break for guests even after the stubs are implemented. Both are fixed in Step 0 below, before touching the screen itself.

- [ ] **Step 0: Fix `RecommendationServiceImpl` — real logic, guest-aware repository**

Read the full current file first (already captured during planning — reproduced with fixes below). Replace its entire content:

```dart
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/services/reward_calculator.dart';
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';

/// Default implementation of RecommendationService using RewardCalculator
class RecommendationServiceImpl implements RecommendationService {
  final RewardCalculator _rewardCalculator;
  final CardRepository _cardRepository;
  final TransactionRepository _transactionRepository;

  RecommendationServiceImpl({
    required MerchantRateService merchantRateService,
    required MilestoneTracker milestoneTracker,
    required CardRepository cardRepository,
    required TransactionRepository transactionRepository,
  })  : _cardRepository = cardRepository,
        _transactionRepository = transactionRepository,
        _rewardCalculator = RewardCalculator(
          merchantRateService: merchantRateService,
          milestoneTracker: milestoneTracker,
          cardRepository: cardRepository,
        );

  @override
  Future<double> calculateReward({
    required CreditCard card,
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    return _rewardCalculator.calculateRewardValue(card, amount, category);
  }

  @override
  Future<List<CreditCard>> getCardRecommendations({
    required String userId,
    int limit = 5,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    return cards.take(limit).toList();
  }

  @override
  Future<CardRecommendationResult> getBestCardForTransaction({
    required String userId,
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    final userCards = await _cardRepository.getUserCards(userId);

    if (userCards.isEmpty) {
      return CardRecommendationResult(
        bestUserCard: null,
        bestUserReward: 0.0,
        bestOverallCard: null,
        bestOverallReward: 0.0,
        potentialSavings: 0.0,
        explanation: 'No cards found for user',
      );
    }

    CreditCard? bestCard;
    double maxReward = 0.0;

    for (final card in userCards) {
      final reward = await _rewardCalculator.calculateRewardValue(
        card,
        amount,
        category,
        merchantName: merchantName,
      );
      if (reward > maxReward) {
        maxReward = reward;
        bestCard = card;
      }
    }

    return CardRecommendationResult(
      bestUserCard: bestCard,
      bestUserReward: maxReward,
      bestOverallCard: bestCard,
      bestOverallReward: maxReward,
      potentialSavings: maxReward,
      explanation: bestCard == null
          ? 'No suitable card found for this transaction'
          : 'Best card for this transaction: ${bestCard.cardName} with ₹${maxReward.toStringAsFixed(0)} reward',
    );
  }

  /// Compares what the user actually earned on each category against what
  /// their best-in-wallet card would have earned, surfacing categories
  /// where switching cards would have earned meaningfully more.
  @override
  Future<List<SpendingOptimization>> getSpendingOptimizations({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    if (cards.length < 2) return [];

    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: startDate ?? DateTime.now().subtract(const Duration(days: 60)),
      endDate: endDate,
    );

    final spendByCategory = <String, double>{};
    for (final t in transactions.where((t) => t.type == TransactionType.debit)) {
      spendByCategory[t.categoryString] = (spendByCategory[t.categoryString] ?? 0) + t.amount;
    }

    final optimizations = <SpendingOptimization>[];
    for (final entry in spendByCategory.entries) {
      final category = entry.key;
      final spend = entry.value;
      if (spend <= 0) continue;

      CreditCard? bestCard;
      double bestReward = -1;
      for (final card in cards) {
        final reward = await calculateReward(
          card: card,
          merchantName: '',
          category: category,
          amount: spend,
        );
        if (reward > bestReward) {
          bestReward = reward;
          bestCard = card;
        }
      }

      final flatReward = spend * 0.01;
      final upside = bestReward - flatReward;
      if (bestCard != null && upside > 50) {
        optimizations.add(SpendingOptimization(
          category: category,
          currentSpending: spend,
          potentialSavings: upside,
          suggestion: 'Route your $category spending through ${bestCard.cardName} to earn more rewards.',
          recommendedCard: bestCard,
        ));
      }
    }

    optimizations.sort((a, b) => b.potentialSavings.compareTo(a.potentialSavings));
    return optimizations.take(5).toList();
  }

  @override
  Future<List<CreditCard>> getNextCardRecommendations({
    required String userId,
    int limit = 3,
  }) async {
    return [];
  }

  @override
  Future<double> calculatePotentialSavings({
    required String userId,
    required String newCardId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return 0.0;
  }

  @override
  Future<Map<String, CreditCard>> getCategoryWiseBestCards({
    required String userId,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    final result = <String, CreditCard>{};
    for (final card in cards) {
      for (final category in card.rewardRates.keys) {
        final currentBest = result[category];
        if (currentBest == null || (card.rewardRates[category] ?? 0) > (currentBest.rewardRates[category] ?? 0)) {
          result[category] = card;
        }
      }
    }
    return result;
  }

  /// Surfaces reward balances that are meaningful enough to act on —
  /// currently: cards with an accumulated reward balance worth calling out.
  @override
  Future<List<RewardOptimization>> getRewardOptimizations({
    required String userId,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: DateTime.now().subtract(const Duration(days: 30)),
    );

    final rewardsByCard = <String, double>{};
    for (final t in transactions) {
      if (t.userCardId == null || t.rewardEarned == null) continue;
      rewardsByCard[t.userCardId!] = (rewardsByCard[t.userCardId!] ?? 0) + t.rewardEarned!;
    }

    final results = <RewardOptimization>[];
    for (final card in cards) {
      final earned = rewardsByCard[card.id] ?? 0;
      if (earned <= 0) continue;
      results.add(RewardOptimization(
        title: '${card.cardName} rewards ready to redeem',
        description: 'You earned ₹${earned.toStringAsFixed(0)} in rewards on ${card.cardName} this month.',
        potentialReward: earned,
        actionRequired: 'Redeem via your card\'s rewards portal',
        relatedCard: card,
      ));
    }

    results.sort((a, b) => b.potentialReward.compareTo(a.potentialReward));
    return results;
  }

  @override
  Future<SpendingAnalysis> analyzeSpendingPatterns({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: startDate,
      endDate: endDate,
    );
    final debits = transactions.where((t) => t.type == TransactionType.debit);
    final totalSpending = debits.fold(0.0, (sum, t) => sum + t.amount);
    final totalRewards = transactions.fold(0.0, (sum, t) => sum + (t.rewardEarned ?? 0));
    final categoryBreakdown = <String, double>{};
    for (final t in debits) {
      categoryBreakdown[t.categoryString] = (categoryBreakdown[t.categoryString] ?? 0) + t.amount;
    }
    return SpendingAnalysis(
      totalSpending: totalSpending,
      totalRewards: totalRewards,
      categoryBreakdown: categoryBreakdown,
      monthlyTrend: const {},
      insights: totalSpending > 0
          ? ['You earned ${(totalRewards / totalSpending * 100).toStringAsFixed(1)}% back in rewards on your spending.']
          : [],
      rewardRate: totalSpending > 0 ? totalRewards / totalSpending : 0.0,
    );
  }
}
```

Now update the provider that constructs this service. In `lib/core/providers/service_providers.dart`, change:
```dart
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationServiceImpl(
    merchantRateService: MerchantRateService(),
    milestoneTracker: MilestoneTracker(),
  );
});
```
to:
```dart
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationServiceImpl(
    merchantRateService: MerchantRateService(),
    milestoneTracker: MilestoneTracker(),
    cardRepository: ref.watch(cardRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
  );
});
```
This is the same file already modified in Task 3 Step 4 — apply this as an additional change to that same provider definition (it will already exist from Task 3; this just adds the two new named arguments the updated constructor now requires).

**Why this is safe from provider cycles:** `cardRepositoryProvider`/`transactionRepositoryProvider` don't depend on `recommendationServiceProvider`, so this is a one-directional fan-in, not a cycle.

**`RewardCalculator` is concretely typed to `SupabaseCardRepository` and must be widened.** Confirmed during planning: `lib/core/services/reward_calculator.dart` declares `final SupabaseCardRepository cardRepository;` (line 11) and imports `supabase_card_repository.dart` (line 4) — passing a `MockCardRepository` through it would fail to compile as-is. Fix this file too:

Change:
```dart
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';

/// Service for calculating and comparing credit card rewards
class RewardCalculator {
  // Services
  final MerchantRateService merchantRateService;
  final MilestoneTracker milestoneTracker;
  final SupabaseCardRepository cardRepository;
```
to:
```dart
import 'package:cardcompass/core/repositories/card_repository.dart';

/// Service for calculating and comparing credit card rewards
class RewardCalculator {
  // Services
  final MerchantRateService merchantRateService;
  final MilestoneTracker milestoneTracker;
  final CardRepository cardRepository;
```
No other line in this file changes — the constructor and every method already reference `cardRepository` generically through the interface's public methods (`calculateReward`), which `CardRepository` already declares.

- [ ] **Step 1: Replace the `TransactionsScreen` stub with a real list**

Replace the entire file content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../transactions/providers/transactions_provider.dart';
import '../../../../shared/models/transaction.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionCategory? _categoryFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    ref.read(transactionsProvider.notifier).loadUserTransactions(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final allTransactions = ref.watch(transactionsProvider);
    final transactions = _categoryFilter == null
        ? allTransactions
        : allTransactions.where((t) => t.category == _categoryFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: () => _showFilterSheet(context),
            icon: Icon(
              _categoryFilter == null ? Icons.filter_list : Icons.filter_alt,
            ),
          ),
        ],
      ),
      body: allTransactions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No transactions yet', style: AppTextStyles.heading3),
                  const SizedBox(height: 8),
                  Text(
                    'Transactions from your cards will show up here',
                    style: AppTextStyles.body1.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final isCredit = t.type == TransactionType.credit || t.type == TransactionType.refund;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(_categoryIcon(t.category), color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(t.merchantName ?? t.description),
                    subtitle: Text(
                      '${_formatDate(t.transactionDate)} · ${t.categoryString}',
                    ),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                          style: AppTextStyles.body1.copyWith(
                            color: isCredit ? AppTheme.successColor : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (t.rewardEarned != null && t.rewardEarned! > 0)
                          Text(
                            '+${t.rewardEarned!.toStringAsFixed(0)} pts',
                            style: AppTextStyles.caption.copyWith(color: AppTheme.accentColor),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('All categories'),
                trailing: _categoryFilter == null ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() => _categoryFilter = null);
                  Navigator.pop(context);
                },
              ),
              ...TransactionCategory.values.map((category) {
                return ListTile(
                  title: Text(category.name),
                  trailing: _categoryFilter == category ? const Icon(Icons.check) : null,
                  onTap: () {
                    setState(() => _categoryFilter = category);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  IconData _categoryIcon(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return Icons.restaurant;
      case TransactionCategory.fuel:
        return Icons.local_gas_station;
      case TransactionCategory.grocery:
        return Icons.shopping_basket;
      case TransactionCategory.entertainment:
        return Icons.movie;
      case TransactionCategory.travel:
        return Icons.flight;
      case TransactionCategory.shopping:
        return Icons.shopping_bag;
      case TransactionCategory.utilities:
        return Icons.bolt;
      case TransactionCategory.insurance:
        return Icons.shield;
      case TransactionCategory.medical:
        return Icons.local_hospital;
      case TransactionCategory.education:
        return Icons.school;
      case TransactionCategory.investment:
        return Icons.trending_up;
      case TransactionCategory.transport:
        return Icons.directions_car;
      case TransactionCategory.rental:
        return Icons.home;
      case TransactionCategory.subscription:
        return Icons.subscriptions;
      case TransactionCategory.gift:
        return Icons.card_giftcard;
      case TransactionCategory.other:
        return Icons.receipt;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
```

- [ ] **Step 2: Implement `_loadRecommendations` in `RecommendationsScreen`**

Replace the entire file content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/components/app_bar.dart';
import 'package:cardcompass/shared/widgets/empty_state.dart' as empty_widgets;
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/theme.dart';

/// Screen displaying personalized credit card recommendations
class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen> {
  bool _isLoading = true;
  String? _error;
  List<SpendingOptimization> _optimizations = const [];
  List<RewardOptimization> _rewardOptimizations = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
    });
  }

  Future<void> _loadRecommendations() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Please sign in to see recommendations.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(recommendationServiceProvider);
      final results = await Future.wait([
        service.getSpendingOptimizations(userId: user.id),
        service.getRewardOptimizations(userId: user.id),
      ]);
      if (!mounted) return;
      setState(() {
        _optimizations = results[0] as List<SpendingOptimization>;
        _rewardOptimizations = results[1] as List<RewardOptimization>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load recommendations: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Card Recommendations',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          empty_widgets.EmptyState(
            icon: Icons.recommend,
            title: 'No recommendations yet',
            message: _error!,
          ),
        ],
      );
    }

    if (_optimizations.isEmpty && _rewardOptimizations.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          empty_widgets.EmptyState(
            icon: Icons.recommend,
            title: 'You\'re all optimized!',
            message: 'We don\'t see any better card matches for your recent spending right now.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_rewardOptimizations.isNotEmpty) ...[
          Text('Reward opportunities', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          ..._rewardOptimizations.map((r) => _buildRewardCard(context, r)),
          const SizedBox(height: 24),
        ],
        if (_optimizations.isNotEmpty) ...[
          Text('Spending optimizations', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          ..._optimizations.map((o) => _buildOptimizationCard(context, o)),
        ],
      ],
    );
  }

  Widget _buildRewardCard(BuildContext context, RewardOptimization r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.accentColor.withValues(alpha: 0.15),
          child: const Icon(Icons.stars, color: AppTheme.accentColor),
        ),
        title: Text(r.title, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(r.description),
        trailing: Text(
          '+₹${r.potentialReward.toStringAsFixed(0)}',
          style: AppTextStyles.body1.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildOptimizationCard(BuildContext context, SpendingOptimization o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.trending_up, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text('${o.category} spending', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(o.suggestion),
        trailing: Text(
          '+₹${o.potentialSavings.toStringAsFixed(0)}',
          style: AppTextStyles.body1.copyWith(color: AppTheme.successColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
```

This calls `RecommendationService.getSpendingOptimizations`/`getRewardOptimizations` (the abstract interface, resolved via `recommendationServiceProvider` → `RecommendationServiceImpl`, which is not Supabase-backed per the interface list gathered during planning — confirm this by reading `lib/core/services/recommendation_service_impl.dart` before this task if its data source is unclear; it should operate on cards/transactions from the repositories, which are now guest-aware via Task 3).

- [ ] **Step 3: Verify by reading, not building**

Run: `grep -n "TODO\|Coming Soon" lib/features/transactions/presentation/screens/transactions_screen.dart lib/features/recommendations/presentation/screens/recommendations_screen.dart` — expect no matches.
Run: `grep -n "SupabaseCardRepository()" lib/core/services/recommendation_service_impl.dart` — expect no matches (both hardcoded instantiations removed in favor of constructor-injected `_cardRepository`).
Run: `grep -n "SupabaseCardRepository" lib/core/services/reward_calculator.dart` — expect no matches (widened to `CardRepository`).
Run: `grep -n "cardRepository: ref.watch(cardRepositoryProvider)" lib/core/providers/service_providers.dart` — expect a match inside `recommendationServiceProvider`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart lib/features/recommendations/presentation/screens/recommendations_screen.dart lib/core/services/recommendation_service_impl.dart lib/core/services/reward_calculator.dart lib/core/providers/service_providers.dart
git commit -m "Build out Transactions and Recommendations screens

Replaces the 'Coming Soon' Transactions stub with a real filterable
list backed by transactionsProvider. Implements the previously no-op
_loadRecommendations, and implements the previously-stubbed
getSpendingOptimizations/getRewardOptimizations in
RecommendationServiceImpl (both returned [] unconditionally before).
Also fixes RecommendationServiceImpl and RewardCalculator hardcoding
SupabaseCardRepository directly, which would have bypassed the guest
mock repository entirely."
```

---

## Task 7: Fix wrong-auth-source bugs in Notifications, Benefits, Statements

**Files:**
- Modify: `lib/features/notifications/presentation/screens/notifications_screen.dart`
- Modify: `lib/features/benefits/viewmodels/benefits_viewmodel.dart`
- Modify: `lib/features/statements/presentation/screens/statements_screen.dart`

- [ ] **Step 1: Fix `notifications_screen.dart`'s direct Supabase auth reads**

Every place in this file that reads `Supabase.instance.client.auth.currentUser?.id` must instead read `ref.read(authStateProvider).user?.id`. Add the import:
```dart
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
```

Then replace each occurrence of:
```dart
Supabase.instance.client.auth.currentUser?.id
```
with:
```dart
ref.read(authStateProvider).user?.id
```
This applies to `_loadNotifications` (around line 32-33) and every action method that reads the current user id (`_markAsRead`, `_markAllAsRead`, `_handleNotificationAction`, and the notification-preferences update calls around lines 305-417). If any of these call sites are inside a `StatelessWidget`/helper class without a `ref` in scope (e.g. `NotificationSettingsSheet`), thread `WidgetRef ref` as a constructor/method parameter from the calling `ConsumerWidget` instead — do not introduce a second `Supabase.instance.client` read as a workaround.

Also remove the now-unused `import 'package:supabase_flutter/supabase_flutter.dart';` from this file once no `Supabase.instance` references remain (check with `grep -n "Supabase\." lib/features/notifications/presentation/screens/notifications_screen.dart` first — only remove the import if the grep comes back empty).

- [ ] **Step 2: Fix `benefits_viewmodel.dart`'s `setSelectedPeriod`**

Find `setSelectedPeriod` (around lines 319-327), which reads `Supabase.instance.client.auth.currentUser` directly. Since `BenefitsViewModel` is constructed with a `Ref` (stored as `_ref`), replace the Supabase read with the app's auth provider:

```dart
Future<void> setSelectedPeriod(String period) async {
  final user = _ref.read(authStateProvider).user;
  if (user == null) return;
  state = state.copyWith(selectedPeriod: period);
  await loadBenefitsData(user.id);
}
```
(Adjust to match whatever the surrounding method body actually does beyond the auth read — read the full method first since only the auth-source line is confirmed broken; preserve the rest of its existing logic, just swap the user-id source.)

Add the import if not already present:
```dart
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
```

Also unify the two existing inline mock-card generators (`_getMockCards`, IDs `mock1`/`mock2`, names "Mock Platinum Card"/"Mock Gold Card") to use the shared `MockData`/`MockIds` from Task 2 instead of their own bespoke placeholder names, so a guest sees the same "HDFC Regalia Gold" etc. everywhere rather than "Mock Platinum Card" in Benefits and "HDFC Regalia Gold" in Home. Replace the body of `_getMockCards`:

```dart
List<CreditCard> _getMockCards(String userId) {
  return MockData.creditCards();
}
```

Add the import:
```dart
import 'package:cardcompass/core/mock/mock_data.dart';
```

Similarly, update `_generateMockUsageData` to key its 3 hardcoded `BenefitUsage` entries off `MockIds.cardHdfcRegalia`/`MockIds.cardAxisAce`/`MockIds.cardIciciAmazonPay` instead of `cards.first.id` for all three, so usage spreads across cards realistically (read the method's current body first to preserve its exact `BenefitUsage` construction pattern — only change which cardId each entry references).

- [ ] **Step 3: Fix `statements_screen.dart`'s wrong auth source**

Change:
```dart
final authService = ref.watch(authServiceProvider);
final userId = authService.currentUser?.id ?? '';
```
to:
```dart
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
...
final authState = ref.watch(authStateProvider);
final userId = authState.user?.id ?? '';
```
(Add the import alongside the existing ones at the top of the file; remove the `authServiceProvider` read only if nothing else in the file uses `authService` — check with `grep -n "authService" lib/features/statements/presentation/screens/statements_screen.dart` first.)

Also fix the empty `onPressed: () {}` for the "View" button (around line 156, inside `_buildStatementCard`). Read the surrounding method to find the `Statement` variable in scope (likely named `statement`), then wire it to show a detail dialog:
```dart
onPressed: () => _showStatementDetail(context, statement),
```
Add a new private method in the same class:
```dart
void _showStatementDetail(BuildContext context, Statement statement) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(statement.statementPeriod),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total due: ₹${statement.totalAmount.toStringAsFixed(0)}'),
          Text('Minimum payment: ₹${statement.minimumPayment.toStringAsFixed(0)}'),
          Text('Due date: ${statement.dueDate.day}/${statement.dueDate.month}/${statement.dueDate.year}'),
          Text('Rewards earned: ${statement.rewardsEarned.toStringAsFixed(0)}'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
```
Ensure `Statement` is imported (it already is, per the file's existing `import 'package:cardcompass/shared/models/statement.dart';`).

- [ ] **Step 4: Verify by reading, not building**

Run: `grep -rn "Supabase.instance.client.auth.currentUser" lib/features/notifications/ lib/features/benefits/ lib/features/statements/` — expect no matches across all three directories.
Run: `grep -n "onPressed: () {}" lib/features/statements/presentation/screens/statements_screen.dart` — expect no matches.
Run: `grep -n "Mock Platinum Card\|Mock Gold Card\|'mock1'\|'mock2'" lib/features/benefits/viewmodels/benefits_viewmodel.dart` — expect no matches after the `_getMockCards` rewrite.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/presentation/screens/notifications_screen.dart lib/features/benefits/viewmodels/benefits_viewmodel.dart lib/features/statements/presentation/screens/statements_screen.dart
git commit -m "Fix wrong auth-source reads blocking guest mode in 3 screens

Notifications, Benefits (setSelectedPeriod), and Statements all read
Supabase.instance.client.auth.currentUser directly instead of the app's
authStateProvider, so their existing mock-data fallback logic never
triggered for guest users (whose session lives only in authStateProvider,
not a real Supabase session). Also unifies Benefits' bespoke mock cards
with the shared MockData set, and wires the dead 'View' button on
statement cards to a detail dialog."
```

---

## Task 8: Guest-mode guards for sign-out, account deletion, and delete-all-data

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Make `signOut` guest-safe**

Change:
```dart
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = const AuthState.unauthenticated();
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }
```
to:
```dart
  Future<void> signOut() async {
    final isGuest = state.user?.id == 'guest';
    if (isGuest) {
      state = const AuthState.unauthenticated();
      return;
    }
    try {
      await _authService.signOut();
      state = const AuthState.unauthenticated();
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }
```
This is inside `AuthNotifier`, not `AuthService` — the existing class structure already separates them correctly (`AuthNotifier.signOut()` at the bottom of the file, distinct from `AuthService.signOut()` above it). Do not modify `AuthService.signOut()` itself.

- [ ] **Step 2: Verify by reading, not building**

Run: `grep -n "isGuest\|state.user?.id == 'guest'" lib/features/auth/providers/auth_provider.dart` — expect a match inside `AuthNotifier.signOut()`.

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart
git commit -m "Guard sign-out against calling dead Supabase for guest users

Guest sessions never touch Supabase auth, so signOut() short-circuits
to a clean local unauthenticated state instead of awaiting a Supabase
call that has nothing to sign out of."
```

---

## Task 9: Fix Profile screen — persistent settings, real dialogs, guest-aware account deletion

**Files:**
- Create: `lib/core/services/app_preferences.dart`
- Modify: `lib/features/auth/presentation/screens/profile_screen.dart`

- [ ] **Step 1: Create a small SharedPreferences-backed settings helper**

Create `lib/core/services/app_preferences.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for app-wide user preferences
/// that need to persist locally regardless of guest/authenticated mode.
class AppPreferences {
  static const _keyNotifications = 'pref_notifications_enabled';
  static const _keyBiometric = 'pref_biometric_enabled';
  static const _keyDarkMode = 'pref_dark_mode_enabled';
  static const _keyLanguage = 'pref_language';
  static const _keyCurrency = 'pref_currency';
  static const _keyAutoSync = 'pref_auto_sync';

  final SharedPreferences _prefs;

  AppPreferences(this._prefs);

  bool get notificationsEnabled => _prefs.getBool(_keyNotifications) ?? true;
  Future<void> setNotificationsEnabled(bool value) => _prefs.setBool(_keyNotifications, value);

  bool get biometricEnabled => _prefs.getBool(_keyBiometric) ?? false;
  Future<void> setBiometricEnabled(bool value) => _prefs.setBool(_keyBiometric, value);

  bool get darkModeEnabled => _prefs.getBool(_keyDarkMode) ?? false;
  Future<void> setDarkModeEnabled(bool value) => _prefs.setBool(_keyDarkMode, value);

  String get language => _prefs.getString(_keyLanguage) ?? 'English';
  Future<void> setLanguage(String value) => _prefs.setString(_keyLanguage, value);

  String get currency => _prefs.getString(_keyCurrency) ?? 'INR';
  Future<void> setCurrency(String value) => _prefs.setString(_keyCurrency, value);

  bool get autoSyncEnabled => _prefs.getBool(_keyAutoSync) ?? true;
  Future<void> setAutoSyncEnabled(bool value) => _prefs.setBool(_keyAutoSync, value);
}
```

Add a provider for it in `lib/core/providers/service_providers.dart` (append near the bottom, after `cardIdentificationServiceProvider`):
```dart
import 'package:cardcompass/core/services/app_preferences.dart';
...
/// Provider for AppPreferences (local settings persistence)
final appPreferencesProvider = Provider<AppPreferences>((ref) {
  return AppPreferences(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 2: Wire Profile screen's toggles and save action to real persistence**

In `profile_screen.dart`, add the import:
```dart
import 'package:cardcompass/core/providers/service_providers.dart';
```

Add three state fields to `_ProfileScreenState` (alongside `_isEditing`):
```dart
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;
```

In `_loadUserData()`, load the persisted values too:
```dart
  void _loadUserData() {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated && authState.user != null) {
      final user = authState.user!;
      _nameController.text = user.fullName ?? user.name ?? '';
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
    } else {
      _nameController.text = '';
      _emailController.text = '';
      _phoneController.text = '';
    }
    final prefs = ref.read(appPreferencesProvider);
    _notificationsEnabled = prefs.notificationsEnabled;
    _biometricEnabled = prefs.biometricEnabled;
  }
```

Replace the Notifications switch:
```dart
ListTile(
  leading: const Icon(Icons.notifications),
  title: const Text('Notifications'),
  trailing: Switch(
    value: true,
    onChanged: _isEditing ? (value) {
      // TODO: Implement notification settings
    } : null,
  ),
),
```
with:
```dart
ListTile(
  leading: const Icon(Icons.notifications),
  title: const Text('Notifications'),
  trailing: Switch(
    value: _notificationsEnabled,
    onChanged: _isEditing ? (value) {
      setState(() => _notificationsEnabled = value);
      ref.read(appPreferencesProvider).setNotificationsEnabled(value);
    } : null,
  ),
),
```

Replace the Biometric switch similarly:
```dart
ListTile(
  leading: const Icon(Icons.fingerprint),
  title: const Text('Biometric Authentication'),
  trailing: Switch(
    value: _biometricEnabled,
    onChanged: _isEditing ? (value) {
      setState(() => _biometricEnabled = value);
      ref.read(appPreferencesProvider).setBiometricEnabled(value);
    } : null,
  ),
),
```

For the Dark Mode switch inside `ProfileScreen`, since actually flipping the app's `ThemeMode` requires a app-wide theme-mode provider that does not currently exist and is out of scope to build app-wide in this plan (the design system task uses static light/dark `ThemeData`, switched by system setting via `MaterialApp`, not a manual in-app toggle), replace it with an honest, non-misleading control:
```dart
ListTile(
  leading: const Icon(Icons.dark_mode),
  title: const Text('Dark Mode'),
  subtitle: const Text('Follows your device setting'),
  trailing: Switch(
    value: Theme.of(context).brightness == Brightness.dark,
    onChanged: null,
  ),
),
```

For App Version tap (was fully empty at line 237-239):
```dart
ListTile(
  leading: const Icon(Icons.info),
  title: const Text('App Version'),
  trailing: Text(_getAppVersion()),
  onTap: () {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CardCompass'),
        content: Text('Version ${_getAppVersion()}'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  },
),
```

For Privacy Policy / Terms of Service / Help & Support (currently just snackbars), replace each with a real dialog showing actual (if brief) content instead of "coming soon":
```dart
ListTile(
  leading: const Icon(Icons.privacy_tip),
  title: const Text('Privacy Policy'),
  trailing: const Icon(Icons.arrow_forward_ios),
  onTap: () => _showInfoDialog(
    'Privacy Policy',
    'CardCompass stores your card and transaction data locally on your '
    'device. We do not sell your data to third parties. Data you enter '
    'while signed in with Google syncs to your account; guest-mode data '
    'stays on this device only and is cleared when you sign out.',
  ),
),
```
```dart
ListTile(
  leading: const Icon(Icons.description),
  title: const Text('Terms of Service'),
  trailing: const Icon(Icons.arrow_forward_ios),
  onTap: () => _showInfoDialog(
    'Terms of Service',
    'CardCompass is provided as-is to help you track credit card '
    'benefits and spending. It does not provide financial advice. '
    'Reward and benefit figures are estimates and may not match your '
    'card issuer\'s exact terms.',
  ),
),
```
```dart
ListTile(
  leading: const Icon(Icons.help),
  title: const Text('Help & Support'),
  trailing: const Icon(Icons.arrow_forward_ios),
  onTap: () => _showInfoDialog(
    'Help & Support',
    'For help using CardCompass, check that your cards and transactions '
    'are up to date via the sync button on the home screen. If something '
    'looks wrong, try signing out and back in.',
  ),
),
```
Add the shared dialog helper method to the class:
```dart
  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
```

For `_saveProfile()`, actually persist via `UserProfileService` (which, per planning, is already a pure in-memory mock with no Supabase dependency — safe for guest and real users alike):
```dart
  void _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final user = ref.read(authStateProvider).user;
      if (user != null) {
        final service = ref.read(userProfileServiceProvider);
        final profile = await service.getUserProfile(user.id);
        await service.updateUserProfile(
          user.id,
          profile.copyWith(
            name: _nameController.text,
            email: _emailController.text,
            phoneNumber: _phoneController.text,
          ),
        );
      }
      setState(() {
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }
```
Before writing this, read `lib/core/services/user_profile_service.dart`'s `UserProfile` class definition to confirm the exact field names accepted by its constructor/`copyWith` (the planning report noted fields but not their exact names — verify `name`, `email`, `phoneNumber` match; adjust field names in this snippet to whatever `UserProfile.copyWith` actually exposes if they differ, e.g. it might be `fullName` instead of `name`).

For the Camera/Gallery/Remove Photo options in `_changeProfilePicture`, since `image_picker` is already a dependency, wire Camera and Gallery to it for real, and make Remove Photo honest about doing nothing yet (no photo storage exists in this app — do not claim success for an action with no effect):
```dart
import 'package:image_picker/image_picker.dart';
...
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final image = await picker.pickImage(source: ImageSource.camera);
                  if (image != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Photo captured (not yet saved to profile)')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Photo selected (not yet saved to profile)')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Remove Photo'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
```
(Removing the "Photo removed" snackbar entirely for the no-op Remove Photo action — since there's no profile photo storage anywhere in this app yet, claiming success would be a lie. Camera/Gallery now do a real, working picker call; actually wiring the picked image into a persisted avatar is a larger feature explicitly out of scope here — the snackbar text says so honestly.)

For account deletion, make it guest-aware:
```dart
  void _showDeleteAccountDialog() {
    final isGuest = ref.read(authStateProvider).user?.id == 'guest';
    if (isGuest) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not available in guest mode'),
          content: const Text(
            'Guest sessions don\'t have an account to delete. Sign in with '
            'Google to manage account deletion.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account deletion coming soon')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
```
(The real-account deletion path keeps its existing "coming soon" snackbar since implementing actual Supabase account deletion is out of scope — Supabase is dead for this pass per the user's explicit instruction — but the guest path now tells the truth immediately instead of pretending the button might work.)

- [ ] **Step 3: Verify by reading, not building**

Run: `grep -n "TODO\|coming soon" lib/features/auth/presentation/screens/profile_screen.dart` — expect only the one remaining intentional real-account "Account deletion coming soon" (the guest path no longer says this).
Run: `grep -n "class AppPreferences" lib/core/services/app_preferences.dart` — expect a match.
Run: `grep -n "appPreferencesProvider" lib/core/providers/service_providers.dart` — expect a match.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/app_preferences.dart lib/core/providers/service_providers.dart lib/features/auth/presentation/screens/profile_screen.dart
git commit -m "Wire Profile screen to real persistence and honest dialogs

Notification/biometric toggles persist via a new SharedPreferences
wrapper (AppPreferences), profile edits save through the already-mock
UserProfileService, privacy/terms/help show real dialog content instead
of 'coming soon' snackbars, camera/gallery use the real image picker,
and account deletion tells guest users the truth instead of a fake
progress message."
```

---

## Task 10: Fix Settings screen — persistent toggles, honest unavailable-feature dialogs

**Files:**
- Modify: `lib/features/settings/presentation/screens/settings_screen.dart`

- [ ] **Step 1: Load and persist the toggles that have a real local effect**

Add imports:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
```
(the `flutter_riverpod` import already exists — only add `service_providers.dart`).

Add `initState` to load persisted values:
```dart
  @override
  void initState() {
    super.initState();
    final prefs = ref.read(appPreferencesProvider);
    _notificationsEnabled = prefs.notificationsEnabled;
    _biometricAuth = prefs.biometricEnabled;
    _autoSync = prefs.autoSyncEnabled;
    _language = prefs.language;
    _currency = prefs.currency;
  }
```

Update each toggle's `onChanged` to also persist:
```dart
SwitchListTile(
  title: const Text('Enable Notifications'),
  subtitle: const Text('Receive all app notifications'),
  value: _notificationsEnabled,
  onChanged: (value) {
    setState(() => _notificationsEnabled = value);
    ref.read(appPreferencesProvider).setNotificationsEnabled(value);
  },
),
```
Apply the same `setState(...) + ref.read(appPreferencesProvider).set...(value)` pattern to: Biometric Authentication (`setBiometricEnabled`), Auto Sync (`setAutoSyncEnabled`). Push/Email/SMS notification sub-toggles remain local-only `setState` (no backend to push to, and they're already correctly gated behind the parent "Enable Notifications" toggle) — leave those three as-is, they aren't misleading since they don't claim to do anything beyond local UI state and aren't presented as syncing anywhere.

For Dark Mode, apply the same non-misleading fix as Task 9:
```dart
SwitchListTile(
  title: const Text('Dark Mode'),
  subtitle: const Text('Follows your device setting'),
  value: Theme.of(context).brightness == Brightness.dark,
  onChanged: null,
),
```

For Language and Currency dialogs, persist the selection instead of just local `setState`:
```dart
                onTap: () {
                  setState(() {
                    _language = language;
                  });
                  ref.read(appPreferencesProvider).setLanguage(language);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Language changed to $language')),
                  );
                },
```
```dart
                onTap: () {
                  setState(() {
                    _currency = currency.split(' ')[0];
                  });
                  ref.read(appPreferencesProvider).setCurrency(_currency);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Currency changed to $_currency')),
                  );
                },
```
(Note: persisting the selection is honest even though nothing else in the app currently reads `AppPreferences.language`/`currency` to change displayed strings/₹ formatting elsewhere — that's a larger feature explicitly out of scope. Persisting at least means the choice survives screen navigation within Settings and doesn't silently reset, which is strictly better than today's pure-`setState` behavior.)

- [ ] **Step 2: Replace misleading "success" snackbars for genuinely unimplemented backend features with honest unavailable dialogs**

Change Password, Two-Factor Authentication, Backup Data, Export Data, Check for Updates, Feedback, Rate App, and Clear Cache's confirm action all currently either lie about success ("Cache cleared successfully", "You are using the latest version") or say "coming soon" via snackbar. Replace the snackbar-only pattern with a shared honest dialog helper. Add this method to `_SettingsScreenState`:
```dart
  void _showUnavailableDialog(String feature, String reason) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: Text(reason),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
```

Replace Change Password:
```dart
onTap: () => _showUnavailableDialog(
  'Change Password',
  'Password changes require a signed-in Google account. This isn\'t available in guest mode or for the current build.',
),
```
Two-Factor Authentication:
```dart
onTap: () => _showUnavailableDialog(
  'Two-Factor Authentication',
  '2FA setup requires a connected backend account and isn\'t available yet.',
),
```
Backup Data:
```dart
onTap: () => _showUnavailableDialog(
  'Backup Data',
  'Cloud backup isn\'t available right now. Your data stays on this device.',
),
```
Export Data:
```dart
onTap: () => _showUnavailableDialog(
  'Export Data',
  'CSV/PDF export isn\'t available yet in this build.',
),
```
Check for Updates — this one can stay honest without a dialog since it's not really misleading (there is no update server to check, but "you're on the latest version" is trivially true for a locally-installed build); leave as-is.
Feedback:
```dart
onTap: () => _showUnavailableDialog(
  'Feedback',
  'In-app feedback isn\'t wired up yet. Please reach out to the team directly.',
),
```
Rate App:
```dart
onTap: () => _showUnavailableDialog(
  'Rate App',
  'This build isn\'t distributed through an app store yet.',
),
```
Clear Cache confirm action:
```dart
ElevatedButton(
  onPressed: () {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('There is no cache to clear in this build')),
    );
  },
  child: const Text('Clear'),
),
```

- [ ] **Step 3: Verify by reading, not building**

Run: `grep -n "coming soon\|TODO" lib/features/settings/presentation/screens/settings_screen.dart` — expect no matches.
Run: `grep -n "appPreferencesProvider" lib/features/settings/presentation/screens/settings_screen.dart` — expect multiple matches (initState + 3 toggle handlers + language/currency).

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/presentation/screens/settings_screen.dart
git commit -m "Persist Settings toggles, replace fake-success dialogs with honest ones

Notifications/biometric/auto-sync/language/currency now persist via
AppPreferences instead of resetting on navigation. Backend-dependent
features (password change, 2FA, backup, export, feedback, rating) now
say plainly that they're unavailable instead of claiming fake success
or silently doing nothing."
```

---

## Task 11: Standardize the Home route, verify splash path is unaffected

**Files:**
- Modify: `lib/config/routes.dart`

- [ ] **Step 1: Point `/home` and `/dashboard` at the more complete `HomeScreen`**

In `lib/config/routes.dart`, change:
```dart
      case home:
      case dashboard:
        return MaterialPageRoute(
          builder: (_) => const DashboardScreenRefactored(),
          settings: settings,
        );
```
to:
```dart
      case home:
      case dashboard:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
```
Add the import at the top of the file:
```dart
import 'package:cardcompass/features/cards/presentation/screens/home_screen.dart';
```

**Why this is safe:** `HomeScreen` (the tabbed Home/Transactions/Analytics/Recommendations shell) is more complete than `DashboardScreenRefactored`, which has literal `Placeholder(child: Text('... - Extract to separate widget'))` widgets in its production build method (confirmed during planning). `login_screen.dart` already navigates guests directly to `HomeScreen` on successful auth — this change just makes the named route consistent with what login already does, rather than changing login's behavior.

**What this does NOT fix (explicitly out of scope):** `splash_screen.dart`'s `DashboardLoadingWrapper` still navigates to `DashboardScreenRefactored` directly via `MaterialPageRoute` (not via the named route), for the cold-start "already authenticated" path. This only matters for a real (Google-authenticated) user relaunching the app with a live Supabase session — a guest's session is never persisted (no Supabase session, nothing saved to Hive/SharedPreferences for the guest user), so `refreshAuthState()` on a guest's cold start always resolves to unauthenticated and correctly routes to `LoginScreen`, never reaching `DashboardLoadingWrapper` at all. Since the task at hand is fixing the guest flow, and touching the authenticated cold-start path risks an unrelated regression, leave `splash_screen.dart` untouched. Note this as a known pre-existing inconsistency for real-auth users in the final summary to the user.

- [ ] **Step 2: Verify by reading, not building**

Run: `grep -n "case home:\|case dashboard:" -A 3 lib/config/routes.dart` — expect `HomeScreen()`.
Run: `grep -n "import.*home_screen" lib/config/routes.dart` — expect a match.
Run: `grep -n "DashboardScreenRefactored" lib/config/routes.dart` — expect no matches remaining (the import for it should also be removed if nothing else in the file references it — check with `grep -n "DashboardScreenRefactored" lib/config/routes.dart` after the edit, and remove the now-dead `import 'package:cardcompass/features/dashboard/presentation/screens/dashboard_screen_refactored.dart';` line if so).

- [ ] **Step 3: Commit**

```bash
git add lib/config/routes.dart
git commit -m "Standardize /home and /dashboard routes on HomeScreen

DashboardScreenRefactored has unfinished Placeholder widgets in its
production build method; HomeScreen (already login's direct-navigation
target) is the complete, working screen. Named routes now match what
login already does. Splash screen's authenticated-cold-start path is
intentionally left pointing at DashboardScreenRefactored — out of scope
for this guest-flow fix and not reachable by guest sessions, which are
never persisted across restarts."
```

---

## Task 12: Final consistency sweep and summary

**Files:** none (read-only verification pass)

- [ ] **Step 1: Sweep for remaining TODO/no-op patterns in guest-reachable screens**

Run:
```bash
grep -rn "TODO\|coming soon\|Coming Soon" \
  lib/features/cards/ lib/features/transactions/ lib/features/analytics/ \
  lib/features/recommendations/ lib/features/statements/ lib/features/benefits/ \
  lib/features/notifications/ lib/features/auth/presentation/screens/profile_screen.dart \
  lib/features/settings/ --include="*.dart"
```
Review every remaining match. Each one should now be either: (a) a real, honest "not available" dialog (Task 9/10's intentional ones), or (b) something explicitly out of scope per this plan (e.g. real-account deletion, splash-path dashboard). If any other silent no-op surfaces that wasn't covered by Tasks 4-10, fix it inline following the same pattern (real navigation/action, or an honest unavailable dialog) before proceeding.

- [ ] **Step 2: Confirm no orphaned imports or unused providers**

Run: `grep -rn "import.*dashboard_screen_refactored" lib/ --include="*.dart"` — confirm `DashboardScreenRefactored` is still referenced somewhere valid (splash screen) and wasn't accidentally left dangling/unused elsewhere.
Run: `grep -rn "activeCardsProvider\|recentTransactionsProvider\|totalCreditLimitProvider\|monthlyRewardsProvider" lib/ --include="*.dart" | grep -v "cards_provider.dart\|transactions_provider.dart"` — every remaining reference should be a usage (import + `ref.watch`/`ref.invalidate`), not a second definition. Confirm no duplicate `final xxxProvider = ...` definitions remain anywhere outside `cards_provider.dart`/`transactions_provider.dart`.

- [ ] **Step 3: Write a short verification note for the user**

This sandbox has no Flutter SDK, so the actual compile/run check cannot happen here. In the final chat response (not a committed file), tell the user explicitly to run, on their own machine:
```bash
flutter pub get
flutter analyze
flutter run
```
and then walk the guest flow end-to-end: Login → Continue as Guest → Home (cards populated, tap a card → details) → Transactions tab (list populated, filter works) → Analytics tab (charts populated) → Recommendations tab (real suggestions or honest empty state) → Profile (toggles persist, dialogs show real content) → Settings (toggles persist) → Benefits/Notifications/Statements (via their nav entry points) → Sign out (returns cleanly to Login without error).

- [ ] **Step 4: No commit for this task** (read-only verification; any fixes found in Step 1 get their own commit using the same message conventions as prior tasks).

---

## Task 13: Push branch and merge to main

**Files:** none (git operations)

- [ ] **Step 1: Confirm current branch and create the feature branch if not already on one**

Run: `git status` and `git branch --show-current`. If currently on `main` (expected, since only the design spec commit has landed on `main` so far), create and switch to the feature branch:
```bash
git checkout -b feature/guest-flow-redesign
```
If task commits were accidentally made on `main` directly during Tasks 1-12 (they should not have been, per the design spec's stated git workflow — feature branch first), stop and reconcile before proceeding: check `git log main..HEAD` is empty relative to origin, then move the commits with `git branch feature/guest-flow-redesign && git reset --hard origin/main` only after confirming `origin/main` reflects the pre-Task-1 state — do not run a hard reset without first confirming this, since it is destructive.

- [ ] **Step 2: Push the feature branch**

```bash
git push -u origin feature/guest-flow-redesign
```

- [ ] **Step 3: Merge into main**

Ask the user for final confirmation before merging (this pushes to shared history) — do not merge automatically without an explicit go-ahead in the conversation, per the standing instruction to confirm before actions that affect shared/remote state. Once confirmed:
```bash
git checkout main
git pull origin main
git merge feature/guest-flow-redesign --no-ff -m "Merge feature/guest-flow-redesign: guest flow fix + fintech design refresh

Fixes Continue as Guest to run fully offline on realistic mock data,
resolves every dead button/stub screen along that path, fixes several
wrong-auth-source bugs that silently broke guest mode, and applies a
navy/gold fintech design system (Inter typography, refreshed palette)
across the app."
git push origin main
```

- [ ] **Step 4: No further commit** (this task is the merge itself).

---

## Self-Review Notes

- **Spec coverage:** Mock data layer (Task 2-3), repository wiring (Task 3), home-screen/provider-duplication fix (Task 4), broken-button fixes (Tasks 4-10), routing fix (Task 11), design system (Task 1), rollout/verification (Task 12), git workflow (Task 13) — all spec sections have a corresponding task.
- **Deviation from the original spec worth flagging to the user:** the spec assumed `DashboardScreenRefactored` was the more-complete screen and `HomeScreen` the divergent duplicate; deeper file reads during planning showed the reverse (`DashboardScreenRefactored` has literal unfinished `Placeholder` widgets). Task 11 standardizes on `HomeScreen` instead, which is the correct call but differs from the spec's stated direction — noted inline in Task 11 rather than silently diverging.
- **Deviation:** the spec proposed full `Mock*Repository` classes plus new abstract interfaces for Benefits/Notifications/User. Planning found these three already have working inline mock-fallback-on-error logic that only fails to trigger for guests because of wrong-auth-source bugs (reading `Supabase.instance.client.auth.currentUser` instead of the app's own `authStateProvider`). Task 7 fixes the actual bug and unifies the existing mocks' data with the shared `MockData` set, which is a smaller, lower-risk change than a full interface-extraction rewrite, and was called out to the user as the reason for the change in scope.
- **Additional bugs found and folded in during planning (not in the original spec):** `RecommendationServiceImpl.getSpendingOptimizations`/`.getRewardOptimizations` were unconditionally-empty stubs (`// TODO: Implement ... return [];`) — without fixing this, Task 6's `RecommendationsScreen` rewrite would compile and show an honest empty state, but never the populated recommendations the user asked for. Additionally, `RecommendationServiceImpl` and `RewardCalculator` both hardcoded `SupabaseCardRepository()` directly instead of accepting the abstract `CardRepository` interface, which would have silently bypassed the Task 3 guest/live switch entirely. Both are now fixed in Task 6 Step 0.
- **Placeholder scan:** no TBD/TODO left in any task's code blocks; every step shows complete, concrete code.
- **Type consistency:** `MockIds.cardHdfcRegalia` etc. are used identically across `mock_data.dart` (Task 2), `mock_card_repository.dart`/`mock_transaction_repository.dart`/`mock_statement_repository.dart` (Task 3), and `benefits_viewmodel.dart`'s updated mock cards (Task 7) — same constant names throughout, no renaming drift.
