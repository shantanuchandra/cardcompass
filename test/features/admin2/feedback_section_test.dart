import 'package:cardcompass/features/admin2/feedback/feedback_models.dart';
import 'package:cardcompass/features/admin2/feedback/feedback_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed page refresh retains the last stable content', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackSection(
            load: ({int page = 1, int limit = 25, String? reviewStatus}) async {
              if (++calls == 2) throw Exception('offline');
              return AdminFeedbackPage(
                items: [
                  AdminFeedbackListItem(
                    id: '10000000-0000-4000-8000-000000000001',
                    feature: 'card_data',
                    reviewStatus: 'eval_created',
                    triageStatus: 'triaged',
                    severity: 'normal',
                    createdAt: DateTime.utc(2026),
                  ),
                ],
                page: page,
                limit: limit,
                total: 101,
              );
            },
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback-next-page')));
    await tester.pumpAndSettle();
    expect(find.text('card_data · eval_created'), findsOneWidget);
    expect(
      find.text('Refresh failed. Showing the last loaded page.'),
      findsOneWidget,
    );
    expect(find.text('Page 1 · 101 total'), findsOneWidget);
  });
}
