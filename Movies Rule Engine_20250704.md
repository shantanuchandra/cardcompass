<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" class="logo" width="120"/>

# Extensible Movie-Ticket Rule Engine for CardCompass

> **Goal** – start with *only* movie offers, yet keep the design generic so that every new benefit (fuel, travel, grocery …) can plug into the same engine without schema changes.

## 1 · Data-layer recap (no schema breakage)

The four tables you already have are all we need:


| Table | Primary key | What it already stores | How the engine will use it |
| :-- | :-- | :-- | :-- |
| `benefit_categories` | `category_code` | “ENTERTAINMENT”, “FUEL”… | movie rules belong to `ENTERTAINMENT` |
| `benefits` | `id` | Name, `calculation_method`, `default_value`, free-text description | one row = one logical movie offer (e.g. “PVR BOGO”) |
| `card_benefits` | `id` | FK `benefit_id`, FK `card_id`, `value`, `spending_categories`, `configuration` (JSONB) | *card-specific* parameters and caps |
| `benefit_tiers` | `id` | FK `card_benefit_id`, `tier_min_value`, `tier_max_value`, `tier_benefit_value` | milestone slabs (e.g. “after ₹10 000 get 2 free tickets”) |

### Zero-touch additions

1. **Enum helper** (optional):

```sql
create type offer_type as enum ('BOGO','PERCENT_DISCOUNT','CASHBACK','MILESTONE');
```

2. **JSON contract** – every movie rule’s `card_benefits.configuration` must follow the contract below. No new columns are added.
```jsonc
{
  "offer_type"            : "BOGO",            // ENUM
  "partner_filter"        : ["BookMyShow"],    // null = any cinema app
  "discount_percent"      : 50,                // for %-discount
  "max_discount_amount"   : 200,               // ₹ cap per txn
  "free_ticket_count"     : 1,                 // for BOGO
  "txn_ticket_limit"      : 2,                 // hard cap per txn
  "month_ticket_limit"    : 4,                 // rolling-30-day cap
  "milestone_currency"    : 10000,             // spend required
  "milestone_reward"      : 2,                 // tickets earned
  "valid_dow"             : ["SAT","SUN"],     // day-of-week filter
  "valid_time"            : "00:00-23:59",     // off-peak etc.
  "start_date"            : "2025-07-01",
  "end_date"              : "2025-09-30"
}
```

All other future benefits (fuel, dining …) will store *their* JSON contracts in the **same** column—no migration pain.

## 2 · Engine architecture (Flutter + Dart)

```
┌────────────┐      movie query      ┌─────────────┐
│ Flutter UI │ ────────────────────▶ │ RuleEngine  │
└────────────┘                       └─────┬───────┘
                                           │ fetches
                                  Supabase │
                                           ▼
                                 movie rules + usage
```


### 2.1 Core abstractions

```dart
enum OfferType { bogo, percentDiscount, cashback, milestone }

class MovieRule {
  MovieRule({
    required this.benefitId,
    required this.offerType,
    required this.config,
    required this.cardName,
  });

  final String benefitId;
  final OfferType offerType;
  final Map<String, dynamic> config; // raw JSON
  final String cardName;
}

class EvalContext {
  EvalContext({
    required this.amount,
    required this.ticketsRequested,
    required this.transactionDate,
    required this.partner,
    required this.userId,
  });

  final double amount;                 // ₹ value of booking
  final int ticketsRequested;          // seats user picks
  final DateTime transactionDate;      // local TZ
  final String partner;                // “BookMyShow”
  final String userId;                 // Supabase uid
}

class EvalResult {
  final String cardName;
  final double userPays;               // final ₹ after benefit
  final double benefitValue;           // ₹ saved
  final String explanation;            // human-friendly
}
```


### 2.2 Engine workflow

```mermaid
flowchart TD
  A[Fetch movie rules for all user cards] --> B{filter by partner & date}
  B --> C{check day-of-week & time}
  C --> D[enforce per-txn caps]
  D --> E[enforce monthly caps (read aggregation view)]
  E --> F[compute benefit ₹]
  F --> G[return top-N cards sorted by userPays asc]
```


## 3 · Reference implementation (pure Dart, web-safe)

```dart
// lib/rules/movie_rule_engine.dart
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart'; // MovieRule, EvalContext, EvalResult, OfferType

class MovieRuleEngine {
  final _client = Supabase.instance.client;

  /// Public API – returns two best options:
  /// (1) best card in user’s wallet  (2) best card overall market
  Future<List<EvalResult>> evaluate(EvalContext ctx) async {
    // 1 ▸ Get active movie benefits for user's cards
    final userRules =
        await _getRules(where: 'user', userId: ctx.userId);

    // 2 ▸ Always fetch market-wide champions for comparison
    final marketRules = await _getRules(where: 'market');

    // 3 ▸ Score each rule set
    final scoredUser = _scoreRules(ctx, userRules);
    final scoredMarket = _scoreRules(ctx, marketRules);

    // 4 ▸ Pick cheapest payable amount from each list
    scoredUser.sort((a, b) => a.userPays.compareTo(b.userPays));
    scoredMarket.sort((a, b) => a.userPays.compareTo(b.userPays));

    return [
      if (scoredUser.isNotEmpty) scoredUser.first,
      if (scoredMarket.isNotEmpty) scoredMarket.first,
    ];
  }

  /* ───────────────────  helpers  ─────────────────── */

  Future<List<MovieRule>> _getRules({
    required String where,
    String? userId,
  }) async {
    // join card_benefits ↔ benefits ↔ (optionally) user_cards
    final query = _client
        .from('card_benefits')
        .select('id,configuration,credit_cards(card_name),benefits(offer_type)')
        .eq('is_active', true)
        .eq('benefits.category_code', 'ENTERTAINMENT');

    if (where == 'user') {
      query.eq('credit_cards.owner_id', userId);
    }

    final data = await query;

    return data.map<MovieRule>((row) {
      return MovieRule(
        benefitId: row['id'] as String,
        cardName: row['credit_cards']['card_name'] as String,
        offerType:
            OfferType.values.firstWhere((e) => e.name.toUpperCase() ==
                (row['benefits']['offer_type'] as String).toUpperCase()),
        config: row['configuration'] as Map<String, dynamic>,
      );
    }).toList();
  }

  List<EvalResult> _scoreRules(
      EvalContext ctx, List<MovieRule> rules) {
    final results = <EvalResult>[];

    for (final rule in rules) {
      if (!_isRuleApplicable(ctx, rule)) continue;

      final benefit = _computeBenefit(ctx, rule);
      if (benefit <= 0) continue;

      results.add(
        EvalResult(
          cardName: rule.cardName,
          benefitValue: benefit,
          userPays: ctx.amount - benefit,
          explanation:
              '${rule.cardName} saves you ₹${benefit.toStringAsFixed(0)}',
        ),
      );
    }

    return results;
  }

  bool _isRuleApplicable(EvalContext ctx, MovieRule rule) {
    final c = rule.config;

    /* 1️⃣ partner filter */
    final partners = (c['partner_filter'] as List?)?.cast<String>();
    if (partners != null &&
        partners.isNotEmpty &&
        !partners.map((e) => e.toLowerCase()).contains(ctx.partner.toLowerCase())) {
      return false;
    }

    /* 2️⃣ date validity */
    DateTime now = ctx.transactionDate;
    if (c['start_date'] != null &&
        now.isBefore(DateTime.parse(c['start_date']))) return false;
    if (c['end_date'] != null &&
        now.isAfter(DateTime.parse(c['end_date']))) return false;

    /* 3️⃣ day-of-week filter */
    final dows = (c['valid_dow'] as List?)?.cast<String>();
    if (dows != null &&
        dows.isNotEmpty &&
        !dows.contains(DateFormat('EEE').format(now).toUpperCase())) {
      return false;
    }

    /* 4️⃣ per-txn ticket limit */
    final limit = c['txn_ticket_limit'] as int? ?? 99;
    if (ctx.ticketsRequested > limit) return false;

    /* 5️⃣ monthly cap – call a Postgres RPC that returns consumption */
    final monthUsed = _monthlyTicketCount(
      ctx.userId,
      rule.benefitId,
      now,
    ); // async but cached
    final monthCap = c['month_ticket_limit'] as int? ?? 999;
    if (monthUsed >= monthCap) return false;

    return true;
  }

  double _computeBenefit(EvalContext ctx, MovieRule rule) {
    final c = rule.config;

    switch (rule.offerType) {
      case OfferType.bogo:
        final free = (c['free_ticket_count'] as int? ?? 1)
            .clamp(0, ctx.ticketsRequested);
        final perTicket = ctx.amount / ctx.ticketsRequested;
        return (free * perTicket)
            .clamp(0, c['max_discount_amount']?.toDouble() ?? double.infinity);
      case OfferType.percentDiscount:
        final pct = (c['discount_percent'] as num?)?.toDouble() ?? 0;
        return (ctx.amount * pct / 100)
            .clamp(0, c['max_discount_amount']?.toDouble() ?? double.infinity);
      case OfferType.cashback:
        final pct = (c['discount_percent'] as num?)?.toDouble() ?? 0;
        return (ctx.amount * pct / 100)
            .clamp(0, c['max_discount_amount']?.toDouble() ?? double.infinity);
      case OfferType.milestone:
        final need = (c['milestone_currency'] as num?)?.toDouble() ?? 0;
        final rewardTix = c['milestone_reward'] as int? ?? 0;
        // fetch YTD spend from a materialized view:
        final spent = _ytdMovieSpend(ctx.userId, rule.cardName);
        if (spent + ctx.amount < need) return 0;
        final perTicket = ctx.amount / ctx.ticketsRequested;
        return rewardTix * perTicket;
    }
  }

  // --- Postgres helper calls ------------------------------------------------

  int _monthlyTicketCount(
      String userId, String benefitId, DateTime now) {
    // This RPC reads a materialized view; stubbed as 0 for sample code.
    return 0;
  }

  double _ytdMovieSpend(String userId, String cardName) {
    // Another RPC / view; 0 for sample.
    return 0.0;
  }
}
```

*Every method contains inline comments; real production code would add exception handling \& logging.*

## 4 · Using the engine in the Flutter web app

```dart
// lib/ui/widgets/movie_checkout_advisor.dart
ElevatedButton(
  onPressed: () async {
    final ctx = EvalContext(
      amount: _totalAmount,
      ticketsRequested: _seatCount,
      transactionDate: DateTime.now(),
      partner: 'BookMyShow',
      userId: supabase.auth.currentUser!.id,
    );

    final engine = MovieRuleEngine();
    final results = await engine.evaluate(ctx);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Best Card to Pay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (results.isEmpty)
              const Text('No active movie offers right now 😔'),
            if (results.isNotEmpty) ...[
              _ResultTile(results[^0], label: 'Best in your wallet'),
              if (results.length == 2) _ResultTile(results[^1], label: 'Best in market'),
            ],
          ],
        ),
      ),
    );
  },
  child: const Text('Which Card Should I Use?'),
);
```


## 5 · Development \& deployment phases

| Phase | Deliverable | Key tasks |
| :-- | :-- | :-- |
| 1. *Schema hardening* | JSON contract docs in repo | agree enum list, create `offer_type` enum, document config keys |
| 2. *Supabase RPCs* | 2 SQL functions (`fn_monthly_ticket_count`, `fn_ytd_movie_spend`) | indexes on `transactions.category_code`, `benefit_id` |
| 3. *Engine MVP* | `movie_rule_engine.dart` (above) | unit tests for each offer type and cap |
| 4. *Flutter integration* | advisory button + dialog (above) | UX polish, error handling, loading states |
| 5. *Analytics \& logging* | Postgres table `rule_engine_logs` | time-series of evaluations for tuning |
| 6. *Future benefits* | add new JSON keys only | no Dart refactor—just implement new `OfferType` subclass |

## 6 · Why this stays flexible

1. **Single source of truth** – every rule lives in `card_benefits.configuration`, so marketing teams can launch / tweak offers without shipping new code.
2. **Pluggable evaluator** – the switch-case in `_computeBenefit` is open for `fuelSurchargeWaiver` tomorrow; all UI and fetching logic stay exactly the same.
3. **Caps \& milestones** – enforced by engine + Postgres views, *not* by hard-coded limits, so changing the cap is a data-only operation.
4. **No extra tables** – you can migrate other benefit categories (fuel, grocery, travel) by adding rows to `benefits` and packing their rules in JSON.

### You can now:

1. Insert sample rows into `benefits` and `card_benefits` with the JSON contract.
2. Copy the Dart files into `lib/rules/`.
3. Call `MovieRuleEngine().evaluate()` from any part of the web app to guide the user at checkout.

Happy shipping!

<div style="text-align: center">⁂</div>

[^1]: image.jpg

[^2]: image.jpg

[^3]: image.jpg

[^4]: image.jpg

