// test/features/benefits/movie_deals/movie_deals_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';

void main() {
  test('movieDealsSearchProvider exposes an unavailable status when not authenticated', () async {
    // currentUserProvider reads Supabase.instance.client, which asserts
    // (fails, not merely returns null) if Supabase.initialize() was never
    // called — as it is not in a bare unit-test process. Overriding
    // currentUserProvider directly lets this test exercise
    // movieDealsSearchProvider's own null-user branch without booting a
    // real (or fake) Supabase client at all.
    final container = ProviderContainer(
      overrides: [currentUserProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    const request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300);
    final result = await container.read(movieDealsSearchProvider(request).future);

    expect(result.status, MovieDealsStatus.unavailable);
  });
}
