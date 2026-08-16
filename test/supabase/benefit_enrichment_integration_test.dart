// End-to-end database safety test against a LIVE LOCAL Supabase stack.
//
// This test deliberately refuses hosted URLs. See test/supabase/README.md for
// the required local reset, keys, and function-serving commands.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_supabase_test_support.dart';

const _serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

final _integrationSkipReason =
    localSupabaseSkipReason ??
    (_serviceRoleKey.isEmpty
        ? 'Requires SUPABASE_SERVICE_ROLE_KEY.'
        : !_isLoopbackUrl(localSupabaseUrl)
        ? 'Refuses non-loopback SUPABASE_URL.'
        : null);

const _knownCardFixture = '''<!doctype html>
<html>
  <head><title>Task 10 Compass Credit Card</title></head>
  <body>
    <h1>Task 10 Compass Credit Card</h1>
    <p>Earn 5 reward points per ₹100 spent on dining.</p>
    <p>Get 10% cashback on dining, capped at ₹500 per statement month.</p>
  </body>
</html>''';

const _crawlerOnlyFixture = '''<!doctype html>
<html>
  <head><title>Task 10 Crawler Only Credit Card</title></head>
  <body>
    <h1>Task 10 Crawler Only Credit Card</h1>
    <p>Get two complimentary domestic lounge visits every quarter.</p>
  </body>
</html>''';

bool _isLoopbackUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return uri.host == '127.0.0.1' ||
      uri.host == 'localhost' ||
      uri.host == '::1';
}

Map<String, dynamic> _row(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> _rows(dynamic value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList(growable: false);

Future<HttpServer> _serveFixtures() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final fixture = switch (request.uri.path) {
      '/known-card' => _knownCardFixture,
      '/crawler-only' => _crawlerOnlyFixture,
      _ => null,
    };
    if (fixture == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = ContentType.html;
      request.response.write(fixture);
    }
    await request.response.close();
  });
  return server;
}

String _sha256(String value) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  final bitLength = bytes.length * 8;
  final paddedLength = ((bytes.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedLength)..setAll(0, bytes);
  padded[bytes.length] = 0x80;
  for (var index = 0; index < 8; index++) {
    padded[paddedLength - 1 - index] = (bitLength >> (index * 8)) & 0xff;
  }

  final hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  int rotateRight(int value, int count) =>
      ((value >>> count) | (value << (32 - count))) & 0xffffffff;

  for (var offset = 0; offset < padded.length; offset += 64) {
    final words = List<int>.filled(64, 0);
    for (var index = 0; index < 16; index++) {
      final start = offset + index * 4;
      words[index] =
          (padded[start] << 24) |
          (padded[start + 1] << 16) |
          (padded[start + 2] << 8) |
          padded[start + 3];
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          rotateRight(words[index - 15], 7) ^
          rotateRight(words[index - 15], 18) ^
          (words[index - 15] >>> 3);
      final s1 =
          rotateRight(words[index - 2], 17) ^
          rotateRight(words[index - 2], 19) ^
          (words[index - 2] >>> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + sum1 + choose + constants[index] + words[index]) & 0xffffffff;
      final sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sum0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }
  return hash.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

Future<Map<String, dynamic>> _insertManualJob(
  SupabaseClient service, {
  required String cardId,
  required String issuer,
  required String sourceUrl,
  required String parserVersion,
}) async {
  return _row(
    await service
        .from('card_catalog_enrichment_jobs')
        .insert({
          'card_id': cardId,
          'issuer': issuer,
          'canonical_url': sourceUrl,
          'final_url_hash': _sha256(sourceUrl),
          'parser_version': parserVersion,
          'status': 'queued',
          'run_mode': 'manual',
        })
        .select()
        .single(),
  );
}

Future<Map<String, dynamic>> _claimManualJob(
  SupabaseClient service,
  String expectedJobId,
) async {
  final claimed = _rows(
    await service.rpc(
      'claim_card_catalog_enrichment_jobs',
      params: {'_max_jobs': 1, '_lease_seconds': 60, '_run_mode': 'manual'},
    ),
  );
  expect(claimed, hasLength(1));
  expect(claimed.single['id'], expectedJobId);
  return claimed.single;
}

Future<Map<String, dynamic>> _stage(
  SupabaseClient service, {
  required Map<String, dynamic> job,
  required String sourceUrl,
  required String parserVersion,
  required String contentHash,
  required Map<String, dynamic> proposal,
}) async {
  final staged = _rows(
    await service.rpc(
      'stage_card_benefit_enrichment',
      params: {
        '_job_id': job['id'],
        '_lease_token': job['lease_token'],
        '_source_url': sourceUrl,
        '_source_url_hash': _sha256(sourceUrl),
        '_parser_version': parserVersion,
        '_content_hash': contentHash,
        '_extracted_data': {
          'request_type': 'official_benefit_enrichment',
          'parser_version': parserVersion,
          'content_hash': contentHash,
          'proposals': [proposal],
          'diff': {
            'additions': [proposal],
            'modifications': <dynamic>[],
            'possibleRemovals': <dynamic>[],
            'unchanged': <dynamic>[],
            'conflicts': <dynamic>[],
          },
        },
        '_calculated_confidence': 0.99,
        '_validation_reasons': [
          {'code': 'official_issuer_source'},
        ],
        '_validation_warnings': <dynamic>[],
        '_source_evidence': [
          {
            'dedupe_key': proposal['dedupeKey'],
            'source_url': sourceUrl,
            'source_excerpt': proposal['sourceExcerpt'],
            'evidence': proposal['evidence'],
          },
        ],
        '_validated_at': DateTime.now().toUtc().toIso8601String(),
      },
    ),
  );
  expect(staged, hasLength(1));
  return staged.single;
}

Future<void> _finalize(
  SupabaseClient service, {
  required Map<String, dynamic> job,
  required String stagingId,
  required String contentHash,
  required bool reused,
}) async {
  final finalized = await service.rpc(
    'finalize_card_catalog_enrichment_job',
    params: {
      '_job_id': job['id'],
      '_lease_token': job['lease_token'],
      '_status': 'staged',
      '_staging_id': stagingId,
      '_content_hash': contentHash,
      '_normalized_fields': {'proposed_count': 1},
      '_result_summary': {
        'proposals': 1,
        'additions': 1,
        'reused_staging': reused,
        'unsafe_mutation_count': 0,
        'raw_body_stored': false,
        'evidence_passed': true,
        'idempotency_passed': true,
      },
      '_failure_category': null,
      '_next_retry_at': null,
    },
  );
  expect(finalized, job['id']);
}

void main() {
  test('local integration safety gate refuses hosted Supabase URLs', () {
    expect(_isLoopbackUrl('https://project.supabase.co'), isFalse);
    expect(_isLoopbackUrl('http://127.0.0.1:54321'), isTrue);
    expect(_isLoopbackUrl('http://localhost:54321'), isTrue);
  });

  test('fixture hashing uses the SHA-256 contract expected by the RPCs', () {
    expect(
      _sha256('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  group('local benefit enrichment integration', () {
    test('deduplicates crawler/service work, recovers leases, reuses staging, '
        'denies queue reads, and applies only approved additions', () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final service = SupabaseClient(localSupabaseUrl, _serviceRoleKey);
      final anonymous = SupabaseClient(localSupabaseUrl, localSupabaseAnonKey);
      final fixtureServer = await _serveFixtures();
      final fixtureBase = Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: fixtureServer.port,
      );
      final knownFixtureUrl = fixtureBase.resolve('/known-card');
      final crawlerFixtureUrl = fixtureBase.resolve('/crawler-only');
      String? knownCardId;
      String? crawlerJobId;
      String? reviewerId;
      final existingDedupeKey = 'task10-existing-$suffix';
      final rejectedDedupeKey = 'task10-rejected-$suffix';
      final approvedDedupeKey = 'task10-approved-$suffix';
      final parserVersion = 'benefits-task10-$suffix';
      final officialKnownUrl =
          'https://www.axis.bank.in/cards/credit-card/task10-$suffix';
      final officialApprovalUrl =
          'https://www.axis.bank.in/cards/credit-card/task10-$suffix/terms';

      try {
        final knownFixture = await http.get(knownFixtureUrl);
        final crawlerFixture = await http.get(crawlerFixtureUrl);
        expect(knownFixture.statusCode, HttpStatus.ok);
        expect(knownFixture.body, _knownCardFixture);
        expect(crawlerFixture.statusCode, HttpStatus.ok);
        expect(crawlerFixture.body, _crawlerOnlyFixture);

        // These endpoint checks prove the local function bundle is being
        // served without allowing the test to fetch a hosted issuer page.
        final functionBase = Uri.parse(
          localSupabaseUrl,
        ).replace(path: '/functions/v1/');
        final anonymousBatch = await http.post(
          functionBase.resolve('benefit-enrichment-batch'),
          body: '{}',
        );
        expect(anonymousBatch.statusCode, HttpStatus.unauthorized);
        final invalidBatch = await http.post(
          functionBase.resolve('benefit-enrichment-batch'),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $_serviceRoleKey',
            HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
          },
          body: jsonEncode({'run_mode': 'unsafe'}),
        );
        expect(invalidBatch.statusCode, HttpStatus.badRequest);
        final anonymousAdmin = await http.post(
          functionBase.resolve('admin-catalog-entry'),
          body: '{}',
        );
        expect(anonymousAdmin.statusCode, HttpStatus.unauthorized);

        for (final table in [
          'card_discovery_jobs',
          'card_catalog_review_queue',
          'card_catalog_enrichment_jobs',
          'card_benefits_staging',
        ]) {
          await expectLater(
            anonymous.from(table).select(),
            throwsA(isA<PostgrestException>()),
            reason: '$table must not be readable by anon',
          );
        }

        final reviewer = await anonymous.auth.signUp(
          email: 'benefit-enrichment-task10-$suffix@example.com',
          password: 'test-password-1234',
        );
        reviewerId = reviewer.user!.id;

        final knownCard = _row(
          await service
              .from('card_catalog')
              .insert({
                'bank': 'Axis Bank',
                'card_name': 'Task 10 Compass $suffix',
                'card_type': 'credit',
                'card_url': officialKnownUrl,
                'is_discontinued': false,
              })
              .select()
              .single(),
        );
        knownCardId = knownCard['id'] as String;

        final existingBenefit = _row(
          await service
              .from('benefits')
              .insert({
                'title': 'Task 10 existing benefit',
                'description': 'Existing live mapping must be retained.',
                'benefit_category': 'DINING',
                'benefit_type': 'reward_points',
                'value_config': {'rate': 1},
                'partners': <dynamic>[],
                'exclusions': <String, dynamic>{},
                'regions': <dynamic>[],
                'dedupe_key': existingDedupeKey,
                'is_active': true,
              })
              .select()
              .single(),
        );
        await service.from('card_benefit_mapping').insert({
          'card_id': knownCardId,
          'benefit_id': existingBenefit['benefit_id'],
          'display_priority': 1,
          'is_primary': true,
          'category_codes': ['DINING'],
        });

        // A crawler-only candidate is service-owned, idempotent, and must
        // remain review-only rather than silently creating a catalog card.
        final crawlerDedupeKey = _sha256(
          'Kotak Bank:task-10-crawler-only-$suffix',
        );
        final crawlerJob = _row(
          await service
              .from('card_discovery_jobs')
              .insert({
                'user_id': null,
                'issuer': 'Kotak Bank',
                'proposed_product': 'Task 10 Crawler Only $suffix',
                'evidence': {
                  'fixture_url': crawlerFixtureUrl.toString(),
                  'html_sha256': _sha256(crawlerFixture.body),
                },
                'dedupe_key': crawlerDedupeKey,
                'status': 'review_required',
                'discovery_source': 'issuer_crawl',
              })
              .select()
              .single(),
        );
        crawlerJobId = crawlerJob['id'] as String;
        final crawlerReview = _row(
          await service
              .from('card_catalog_review_queue')
              .insert({
                'discovery_job_id': crawlerJobId,
                'proposed_fields': {
                  'bank': 'Kotak Bank',
                  'card_name': 'Task 10 Crawler Only $suffix',
                },
                'source_evidence': {
                  'fixture_url': crawlerFixtureUrl.toString(),
                  'html_sha256': _sha256(crawlerFixture.body),
                },
                'validation_warnings': ['crawler_only_requires_review'],
                'confidence': 0.99,
                'status': 'pending',
              })
              .select()
              .single(),
        );
        await service
            .from('card_discovery_jobs')
            .update({'review_item_id': crawlerReview['id']})
            .eq('id', crawlerJobId);
        await expectLater(
          service.from('card_discovery_jobs').insert({
            'user_id': null,
            'issuer': 'Kotak Bank',
            'proposed_product': 'Task 10 Crawler Only $suffix',
            'evidence': <String, dynamic>{},
            'dedupe_key': crawlerDedupeKey,
            'status': 'review_required',
            'discovery_source': 'issuer_crawl',
          }),
          throwsA(isA<PostgrestException>()),
        );
        final crawlerRows = await service
            .from('card_discovery_jobs')
            .select('id,status,review_item_id')
            .eq('discovery_source', 'issuer_crawl')
            .eq('dedupe_key', crawlerDedupeKey);
        expect(crawlerRows, hasLength(1));
        expect(crawlerRows.single['status'], 'review_required');
        expect(crawlerRows.single['review_item_id'], crawlerReview['id']);
        final accidentalCrawlerCard = await service
            .from('card_catalog')
            .select('id')
            .eq('bank', 'Kotak Bank')
            .eq('card_name', 'Task 10 Crawler Only $suffix');
        expect(accidentalCrawlerCard, isEmpty);

        final rejectedProposal = <String, dynamic>{
          'dedupeKey': rejectedDedupeKey,
          'title': 'Task 10 rejected cashback',
          'description': '10% cashback capped at ₹500 per statement month.',
          'category': 'DINING',
          'valueType': 'cashback',
          'rate': 10,
          'cap': 500,
          'period': 'statement month',
          'sourceUrl': officialKnownUrl,
          'sourceExcerpt':
              'Get 10% cashback on dining, capped at ₹500 per statement month.',
          'evidence': {
            'title': '10% cashback on dining',
            'rate': '10% cashback',
            'cap': 'capped at ₹500',
            'period': 'per statement month',
          },
        };
        final rejectedContentHash = _sha256(knownFixture.body);
        final rejectedJob = await _insertManualJob(
          service,
          cardId: knownCardId,
          issuer: 'Axis Bank',
          sourceUrl: officialKnownUrl,
          parserVersion: parserVersion,
        );
        var claimedRejected = await _claimManualJob(
          service,
          rejectedJob['id'] as String,
        );
        final firstLeaseToken = claimedRejected['lease_token'];
        await service
            .from('card_catalog_enrichment_jobs')
            .update({
              'lease_expires_at': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            })
            .eq('id', rejectedJob['id']);
        claimedRejected = await _claimManualJob(
          service,
          rejectedJob['id'] as String,
        );
        expect(claimedRejected['attempt_count'], 2);
        expect(claimedRejected['lease_token'], isNot(firstLeaseToken));

        final firstStage = await _stage(
          service,
          job: claimedRejected,
          sourceUrl: officialKnownUrl,
          parserVersion: parserVersion,
          contentHash: rejectedContentHash,
          proposal: rejectedProposal,
        );
        expect(firstStage['reused'], isFalse);
        await _finalize(
          service,
          job: claimedRejected,
          stagingId: firstStage['staging_id'] as String,
          contentHash: rejectedContentHash,
          reused: false,
        );

        await service
            .from('card_catalog_enrichment_jobs')
            .update({
              'status': 'queued',
              'staging_id': null,
              'content_hash': null,
            })
            .eq('id', rejectedJob['id']);
        final repeatedClaim = await _claimManualJob(
          service,
          rejectedJob['id'] as String,
        );
        final repeatedStage = await _stage(
          service,
          job: repeatedClaim,
          sourceUrl: officialKnownUrl,
          parserVersion: parserVersion,
          contentHash: rejectedContentHash,
          proposal: rejectedProposal,
        );
        expect(repeatedStage['reused'], isTrue);
        expect(repeatedStage['staging_id'], firstStage['staging_id']);
        await _finalize(
          service,
          job: repeatedClaim,
          stagingId: repeatedStage['staging_id'] as String,
          contentHash: rejectedContentHash,
          reused: true,
        );
        final oneStagingRow = await service
            .from('card_benefits_staging')
            .select('id')
            .eq('card_id', knownCardId)
            .eq('source_url_hash', _sha256(officialKnownUrl))
            .eq('parser_version', parserVersion)
            .eq('content_hash', rejectedContentHash);
        expect(oneStagingRow, hasLength(1));

        final liveBenefitsBeforeReject = await service
            .from('benefits')
            .select('benefit_id')
            .inFilter('dedupe_key', [existingDedupeKey, rejectedDedupeKey]);
        final liveMappingsBeforeReject = await service
            .from('card_benefit_mapping')
            .select('mapping_id')
            .eq('card_id', knownCardId);
        final rejection = _rows(
          await service.rpc(
            'approve_card_benefit_enrichment',
            params: {
              '_staging_id': firstStage['staging_id'],
              '_reviewed_by': reviewerId,
              '_decisions': [
                {
                  'action': 'reject',
                  'change_type': 'addition',
                  'dedupe_key': rejectedDedupeKey,
                  'benefit': rejectedProposal,
                  'reason': 'Deterministic Task 10 rejection',
                },
              ],
            },
          ),
        );
        expect(rejection.single['resulting_status'], 'rejected');
        final liveBenefitsAfterReject = await service
            .from('benefits')
            .select('benefit_id')
            .inFilter('dedupe_key', [existingDedupeKey, rejectedDedupeKey]);
        final liveMappingsAfterReject = await service
            .from('card_benefit_mapping')
            .select('mapping_id')
            .eq('card_id', knownCardId);
        expect(liveBenefitsAfterReject.length, liveBenefitsBeforeReject.length);
        expect(liveMappingsAfterReject.length, liveMappingsBeforeReject.length);

        final approvedProposal = <String, dynamic>{
          'dedupeKey': approvedDedupeKey,
          'title': 'Task 10 approved reward points',
          'description': 'Earn 5 reward points per ₹100 spent on dining.',
          'category': 'DINING',
          'valueType': 'reward_points',
          'rate': 5,
          'sourceUrl': officialApprovalUrl,
          'sourceExcerpt': 'Earn 5 reward points per ₹100 spent on dining.',
          'evidence': {
            'title': '5 reward points',
            'rate': '5 reward points per ₹100',
          },
        };
        final approvedJob = await _insertManualJob(
          service,
          cardId: knownCardId,
          issuer: 'Axis Bank',
          sourceUrl: officialApprovalUrl,
          parserVersion: parserVersion,
        );
        final claimedApproved = await _claimManualJob(
          service,
          approvedJob['id'] as String,
        );
        final approvedContentHash = _sha256('${knownFixture.body}\napproval');
        final approvedStage = await _stage(
          service,
          job: claimedApproved,
          sourceUrl: officialApprovalUrl,
          parserVersion: parserVersion,
          contentHash: approvedContentHash,
          proposal: approvedProposal,
        );
        await _finalize(
          service,
          job: claimedApproved,
          stagingId: approvedStage['staging_id'] as String,
          contentHash: approvedContentHash,
          reused: false,
        );
        final approval = _rows(
          await service.rpc(
            'approve_card_benefit_enrichment',
            params: {
              '_staging_id': approvedStage['staging_id'],
              '_reviewed_by': reviewerId,
              '_decisions': [
                {
                  'action': 'approve',
                  'change_type': 'addition',
                  'dedupe_key': approvedDedupeKey,
                  'benefit': approvedProposal,
                },
              ],
            },
          ),
        );
        expect(approval.single['resulting_status'], 'approved');
        final approvedBenefits = await service
            .from('benefits')
            .select('benefit_id,dedupe_key')
            .eq('dedupe_key', approvedDedupeKey);
        expect(approvedBenefits, hasLength(1));
        final approvedMappings = await service
            .from('card_benefit_mapping')
            .select('mapping_id')
            .eq('card_id', knownCardId)
            .eq('benefit_id', approvedBenefits.single['benefit_id']);
        expect(approvedMappings, hasLength(1));
        final finalMappings = await service
            .from('card_benefit_mapping')
            .select('mapping_id')
            .eq('card_id', knownCardId);
        expect(finalMappings.length, liveMappingsBeforeReject.length + 1);
      } finally {
        await fixtureServer.close(force: true);
        if (crawlerJobId != null) {
          await service
              .from('card_discovery_jobs')
              .delete()
              .eq('id', crawlerJobId);
        }
        if (knownCardId != null) {
          await service.from('card_catalog').delete().eq('id', knownCardId);
        }
        await service.from('benefits').delete().inFilter('dedupe_key', [
          existingDedupeKey,
          rejectedDedupeKey,
          approvedDedupeKey,
        ]);
        if (reviewerId != null) {
          await service.auth.admin.deleteUser(reviewerId);
        }
        service.dispose();
        anonymous.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: _integrationSkipReason);
}
