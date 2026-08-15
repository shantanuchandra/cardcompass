import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Single source of truth for how each of the 16 transaction categories is
/// displayed (icon + color) — replaces three previously-independent,
/// drifting copies of this mapping in dashboard_screen.dart,
/// transactions_screen.dart, and card_detail_screen.dart, each of which
/// covered a different, incomplete subset of categories.
///
/// Also maps a few known-legacy category strings ('dining', 'groceries',
/// 'health') to the same icon/color as their current equivalents ('food',
/// 'grocery', 'medical'). These are NOT in transaction_categorizer.dart's
/// `validCategories` and are no longer produced by the categorizer, but
/// migration 20260816000200_validate_transactions_category_check.sql
/// documents that its own precondition — the category-backfill job having
/// actually completed against production data — is unverified in this
/// environment (no Docker/local Supabase), and the transactions_category_valid
/// constraint added in 20260816000100 is NOT VALID (blocks new bad writes
/// only, does not guarantee existing rows are clean). So pre-existing rows
/// with these legacy values may still be live in the database; keeping the
/// aliases here avoids silently downgrading those specific transactions to
/// the generic default icon/color.
IconData categoryIcon(String? category) {
  switch (category?.toLowerCase()) {
    case 'food':
    case 'dining': // legacy alias — see file doc comment
      return Icons.restaurant_rounded;
    case 'fuel': return Icons.local_gas_station_rounded;
    case 'grocery':
    case 'groceries': // legacy alias — see file doc comment
      return Icons.local_grocery_store_rounded;
    case 'entertainment': return Icons.theaters_rounded;
    case 'travel': return Icons.flight_rounded;
    case 'shopping': return Icons.shopping_bag_rounded;
    case 'utilities': return Icons.bolt_rounded;
    case 'insurance': return Icons.shield_rounded;
    case 'medical':
    case 'health': // legacy alias — see file doc comment
      return Icons.medical_services_rounded;
    case 'education': return Icons.school_rounded;
    case 'investment': return Icons.trending_up_rounded;
    case 'transport': return Icons.directions_car_rounded;
    case 'rental': return Icons.home_work_rounded;
    case 'subscription': return Icons.subscriptions_rounded;
    case 'gift': return Icons.card_giftcard_rounded;
    case 'other': return Icons.receipt_rounded;
    default: return Icons.receipt_rounded;
  }
}

Color categoryColor(String? category) {
  switch (category?.toLowerCase()) {
    case 'food':
    case 'dining': // legacy alias — see file doc comment
      return AppColors.warning;
    case 'fuel': return const Color(0xFFF97316);
    case 'grocery':
    case 'groceries': // legacy alias — see file doc comment
      return AppColors.success;
    case 'entertainment': return const Color(0xFFEC4899);
    case 'travel': return const Color(0xFF38BDF8);
    case 'shopping': return AppColors.violet;
    case 'utilities': return const Color(0xFFFBBF24);
    case 'insurance': return const Color(0xFF64748B);
    case 'medical':
    case 'health': // legacy alias — see file doc comment
      return const Color(0xFFEF4444);
    case 'education': return const Color(0xFF6366F1);
    case 'investment': return const Color(0xFF10B981);
    case 'transport': return const Color(0xFF0EA5E9);
    case 'rental': return const Color(0xFF8B5CF6);
    case 'subscription': return const Color(0xFFA855F7);
    case 'gift': return const Color(0xFFF472B6);
    case 'other': return AppColors.textSecondary;
    default: return AppColors.textSecondary;
  }
}
