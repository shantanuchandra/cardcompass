// Integration test against a real Supabase/Postgres instance (local by
// default). Requires SUPABASE_URL/SUPABASE_ANON_KEY to point at a database
// where the 20260714030000_reward_balances_view.sql migration has been
// applied, and two auth users/seed rows created ahead of time (see
// docs/superpowers/plans — this file documents the exact seed used).
// Skips entirely if no Supabase config is present.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cardcompass/core/app_config.dart';
import 'package:cardcompass/core/repositories/supabase_reward_balance_repository.dart';

void main() {
  final hasSupabaseConfig = AppConfig.supabaseUrl.isNotEmpty &&
      AppConfig.supabaseAnonKey.isNotEmpty &&
      Uri.tryParse(AppConfig.supabaseUrl)?.hasAuthority == true;

  const testUserId = '12181f46-124c-4736-9229-49ead2d78824';
  const testUserEmail = 'integrationtest@example.com';
  const otherUserCardId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const password = 'testpassword123';

  SupabaseClient? client;

  setUpAll(() async {
    if (!hasSupabaseConfig) return;
    SharedPreferences.setMockInitialValues({});
    try {
      client = Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      client = Supabase.instance.client;
    }
    await client!.auth.signInWithPassword(email: testUserEmail, password: password);
  });

  test(
    'getUserRewardBalances aggregates real transactions and resolves expiry via card_catalog',
    () async {
      if (!hasSupabaseConfig) {
        markTestSkipped('No Supabase config present — skipping integration test.');
        return;
      }

      final repository = SupabaseRewardBalanceRepository();
      final balances = await repository.getUserRewardBalances(testUserId);

      expect(balances, isNotEmpty,
          reason: 'Expected seeded cashback transactions to produce a balance row.');

      final cashback = balances.firstWhere((b) => b.rewardType == 'cashback');
      expect(cashback.availableBalance, 80.0);
      expect(cashback.totalEarned, 80.0);
      expect(cashback.totalRedeemed, 0.0);
      // HDFC Millennia is mapped as a non-expiring cashback card.
      expect(cashback.expiryDate, isNull);
    },
    skip: !hasSupabaseConfig,
  );

  test(
    "getUserRewardBalances does not leak another user's balances (RLS)",
    () async {
      if (!hasSupabaseConfig) {
        markTestSkipped('No Supabase config present — skipping integration test.');
        return;
      }

      final repository = SupabaseRewardBalanceRepository();
      final balances = await repository.getUserRewardBalances(testUserId);

      expect(
        balances.every((b) => b.userCardId != otherUserCardId),
        isTrue,
        reason: "Another user's reward balance leaked into this query.",
      );
    },
    skip: !hasSupabaseConfig,
  );

  test(
    'redeemRewards throws because no redemption data source exists yet',
    () async {
      if (!hasSupabaseConfig) {
        markTestSkipped('No Supabase config present — skipping integration test.');
        return;
      }

      final repository = SupabaseRewardBalanceRepository();
      expect(
        () => repository.redeemRewards(
          userId: testUserId,
          userCardId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          rewardBalanceId: 'whatever',
          pointsToRedeem: 1,
          redemptionType: 'voucher',
          redemptionValue: 1,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    },
    skip: !hasSupabaseConfig,
  );
}
