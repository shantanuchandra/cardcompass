# Task 4 implementation report

## Outcome

- Added immutable, defensive Card Data models for both identity and benefit lanes, including bounded evidence projections, page metadata, action types, and response receipt timestamps.
- Added typed Inbox snapshots with ranked item metadata, typed Card Data destinations, partial-source failures, and the server refresh timestamp.
- Added shared `AdminOperatorRepository.invoke` transport behavior with safe 401, 403, 409, stable validation, network, and malformed-response mapping.
- Added exact action serialization with generated request IDs, observed timestamps, staging IDs, reasons, and lane-specific payload fields.

## TDD evidence

- Initial RED: focused tests failed at compile time because the four DTO/repository files did not exist.
- Second RED: an invocation-time Supabase 409 was normalized to `request_failed` instead of the required typed state conflict.
- GREEN: focused Card Data and Inbox repository tests passed 19/19.
- Regression: repository plus existing admin access/screen tests passed 44/44.
- Targeted `flutter analyze --no-fatal-infos` completed with no issues.

## Risks

- Card Data list freshness is measured at client receipt because its current server DTO does not contain `refreshed_at`; Inbox uses its authoritative server timestamp.
- Action payloads intentionally remain shaped like the gateway's top-level mutation contract; reserved transport keys cannot be supplied through the payload map.

## Review fixes

- Enforced the complete identity/benefit action matrix locally, including exact top-level fields, UUID/timestamp shape, staging and decision requirements, operation-specific decision actions, required reasons, and nested field allowlists.
- Replaced shallow wrappers with recursive JSON copying and freezing for action payloads and parsed DTO maps/lists; unsupported runtime objects and non-finite numbers fail safely.
- Normalized unexpected SDK, socket, timeout, decoding, and runtime invocation failures to `AdminRequestFailed('request_failed')` while preserving recognized typed exceptions.
- Review RED produced 13 focused failures across the three findings. Review GREEN passed the full Admin2 suite 63/63; targeted analysis reported no issues.

## Boundary follow-up

- Mirrored the Edge validator's 100-character timestamp maximum, 500-character identity text projection, 1,000-character reason maximum, and inclusive 32,768-byte payload cap.
- Payload size uses encoded JSON UTF-8 bytes, not Dart code units, and checks the submitted form plus the reject form after normalized reason injection.
- Boundary coverage accepts 32,767 and 32,768 bytes, rejects a 32,769-byte multibyte case, rejects normalized reject overflow, and isolates a parseable timestamp longer than 100 characters.
- Focused repositories passed 41/41; the full Admin2 suite passed 68/68; targeted analysis reported no issues.
