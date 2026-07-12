import 'package:cardcompass/shared/models/reward_balance.dart';

/// A single actionable reward insight generated for one of the user's cards.
class RewardInsight {
  final String userCardId;
  final String cardDisplayName;
  final InsightType type;
  final String title;
  final String body;
  final String priority; // 'low' | 'medium' | 'high' | 'urgent'
  final Map<String, dynamic> metadata;

  const RewardInsight({
    required this.userCardId,
    required this.cardDisplayName,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    this.metadata = const {},
  });
}

enum InsightType {
  pointsExpiryUrgent, // expiry within 7 days
  pointsExpirySoon,   // expiry within 8–30 days
  highValuePoints,    // large unredeemed balance worth >= ₹500
  redemptionTip,      // guidance on the best redemption path
}

// ---------------------------------------------------------------------------
// Per-bank point-to-INR conversion rates
//
// Source: publicly available bank reward programme documents, mid-2025.
// Update periodically as banks revise their programmes.
// ---------------------------------------------------------------------------
const Map<String, double> _bankPointValueINR = {
  // HDFC
  'hdfc diners black': 0.50,
  'hdfc infinia': 0.50,
  'hdfc regalia gold': 0.35,
  'hdfc regalia': 0.25,
  'hdfc millennia': 0.20,
  'hdfc moneyback': 0.20,
  'hdfc': 0.25,

  // ICICI
  'icici emeralde': 0.33,
  'icici sapphiro': 0.25,
  'icici coral': 0.20,
  'icici': 0.20,

  // SBI
  'sbi cashback': 1.00,   // cashback card — 1 pt = ₹1
  'sbi elite': 0.25,
  'sbi prime': 0.25,
  'sbi simplysave': 0.20,
  'sbi': 0.25,

  // Axis
  'axis atlas': 1.00,     // EDGE Miles
  'axis magnus': 0.35,
  'axis ace': 1.00,
  'axis flipkart': 1.00,
  'axis': 0.20,

  // Kotak
  'kotak league': 0.25,
  'kotak white': 0.25,
  'kotak': 0.25,

  // IndusInd
  'indusind legend': 0.50,
  'indusind pinnacle': 0.33,
  'indusind': 0.20,

  // American Express
  'american express platinum': 0.50,
  'american express gold': 0.33,
  'amex': 0.33,

  // IDFC First
  'idfc first wealth': 1.00,
  'idfc first select': 1.00,
  'idfc': 0.50,

  // Yes Bank
  'yes first exclusive': 0.25,
  'yes': 0.20,

  // RBL
  'rbl fun plus': 0.25,
  'rbl': 0.25,

  // AU Small Finance
  'au zenith': 0.33,
  'au': 0.25,

  // HSBC
  'hsbc premier': 0.33,
  'hsbc': 0.25,

  // Fallback
  'default': 0.25,
};

/// Returns the INR value of 1 reward point / mile / cashback unit for [cardName].
double pointValueFor(String cardName) {
  final lower = cardName.toLowerCase();
  for (final entry in _bankPointValueINR.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return _bankPointValueINR['default']!;
}

/// Analyses [RewardBalance] objects and produces ranked [RewardInsight]s.
///
/// Detects:
///   • Urgent expiry  — expiry within 7 days
///   • Near expiry    — expiry within 8–30 days
///   • High balance   — unredeemed balance worth >= ₹500 with no expiry risk
///   • Redemption tip — best redemption path for the card
class RewardIntelligenceService {
  /// Run full analysis for a user's reward balances.
  ///
  /// [balances]  — from [SupabaseRewardBalanceRepository.getUserRewardBalances]
  /// [cardNames] — map of userCardId → human-readable card name
  List<RewardInsight> analyse({
    required List<RewardBalance> balances,
    required Map<String, String> cardNames,
  }) {
    final insights = <RewardInsight>[];

    for (final balance in balances) {
      if (balance.availableBalance <= 0) continue;

      final name = cardNames[balance.userCardId] ?? 'Your card';
      final pointVal = pointValueFor(name);
      final balanceINR = balance.availableBalance * pointVal;

      // ── Expiry insights ──────────────────────────────────────────────
      if (balance.expiryDate != null) {
        final daysLeft = balance.expiryDate!.difference(DateTime.now()).inDays;

        if (daysLeft > 0 && daysLeft <= 7) {
          insights.add(RewardInsight(
            userCardId: balance.userCardId,
            cardDisplayName: name,
            type: InsightType.pointsExpiryUrgent,
            title: '🚨 ${balance.formattedBalance} expire in $daysLeft day${daysLeft == 1 ? "" : "s"}',
            body: '${balance.formattedBalance} on $name '
                '(≈₹${balanceINR.toStringAsFixed(0)}) expire on '
                '${_fmt(balance.expiryDate!)}. Redeem now before they\'re gone!',
            priority: 'urgent',
            metadata: {
              'expiry_date': balance.expiryDate!.toIso8601String(),
              'balance_inr': balanceINR,
              'days_left': daysLeft,
            },
          ));
          continue; // Skip other insights if already in urgent expiry
        }

        if (daysLeft > 7 && daysLeft <= 30) {
          insights.add(RewardInsight(
            userCardId: balance.userCardId,
            cardDisplayName: name,
            type: InsightType.pointsExpirySoon,
            title: '⏳ Points expire ${_fmt(balance.expiryDate!)}',
            body: '${balance.formattedBalance} on $name '
                '(≈₹${balanceINR.toStringAsFixed(0)}) expire in $daysLeft days. '
                'Best redemption: ${_bestRedemptionFor(name)}.',
            priority: 'high',
            metadata: {
              'expiry_date': balance.expiryDate!.toIso8601String(),
              'balance_inr': balanceINR,
              'days_left': daysLeft,
            },
          ));
          continue;
        }
      }

      // ── High unredeemed balance insight ──────────────────────────────
      if (balanceINR >= 500) {
        insights.add(RewardInsight(
          userCardId: balance.userCardId,
          cardDisplayName: name,
          type: InsightType.highValuePoints,
          title: '💰 ₹${balanceINR.toStringAsFixed(0)} sitting idle on $name',
          body: '${balance.formattedBalance} is worth '
              '≈₹${balanceINR.toStringAsFixed(0)}. '
              '${_bestRedemptionFor(name)} gives you the most value.',
          priority: 'medium',
          metadata: {
            'balance_inr': balanceINR,
            'reward_type': balance.rewardType,
          },
        ));
      }
    }

    // Sort: urgent → high → medium → low
    const _order = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
    insights.sort(
        (a, b) => (_order[a.priority] ?? 3).compareTo(_order[b.priority] ?? 3));

    return insights;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  String _bestRedemptionFor(String cardName) {
    final lower = cardName.toLowerCase();
    if (lower.contains('diners') || lower.contains('infinia')) {
      return 'SmartBuy flights/hotels (best value at ₹0.50/pt)';
    }
    if (lower.contains('atlas') || lower.contains('magnus')) {
      return 'Airline miles transfer (best value)';
    }
    if (lower.contains('amex') || lower.contains('american express')) {
      return 'Marriott/Hilton transfer or Amex Travel';
    }
    if (lower.contains('cashback') || lower.contains('ace') ||
        lower.contains('wealth') || lower.contains('select')) {
      return 'automatic cashback to your statement';
    }
    return 'vouchers or statement credit via net banking';
  }
}
