# Cutover Task 1 report

## Outcome

The Card Data parity contract now executes all 13 required list and mutation workflows through the production UI and typed repository boundary. It found and fixed one genuine gap: benefit recovery actions were blocked locally because the UI supplied a decision-only staging ID.

## TDD evidence

- RED: `flutter test test/features/admin2/admin2_parity_test.dart` failed because benefit retry produced no `card-review-action` invocation.
- Fix: `CardDataSection` now includes `stagingId` only for benefit approve, edit-and-approve, and reject operations.
- GREEN: `flutter test test/features/admin2/admin2_parity_test.dart test/features/admin2/card_data_section_test.dart` passes 21/21.
- Regression: `flutter test test/features/admin2` passes 149/149; `flutter analyze test/features/admin2 lib/features/admin2` reports no issues.

## Contract coverage

- Exact action set: identity/benefit list plus approve, editApprove, merge, reject, retry, quarantine, and unquarantine as applicable.
- One mutation per operator action, with literal wire operation and payload assertions.
- No direct table writes or bulk approval surface.
- Controls lock during submission; refresh starts only after server success.
- Realistic eligible item statuses, evidence, merge candidate, and benefit proposal data are used for every workflow.

## Production gap resolved

Benefit retry, quarantine, and unquarantine previously inherited `item.stagingId`, while `CardDataRepository` and the server contract reject staging IDs for recovery operations. The UI now omits it for those three operations.
