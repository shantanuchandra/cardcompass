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
const _officialBenefitIssuer = String.fromEnvironment(
  'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER',
);
const _officialBenefitUrl = String.fromEnvironment(
  'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL',
);
const _officialBenefitCardName = String.fromEnvironment(
  'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME',
);
const _officialDiscoveryIssuer = String.fromEnvironment(
  'SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER',
);
const _officialDiscoveryUrl = String.fromEnvironment(
  'SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL',
);
const _officialDiscoveryCardName = String.fromEnvironment(
  'SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_CARD_NAME',
);
const _officialDiscoveryExpectedNewProduct = String.fromEnvironment(
  'SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT',
);

List<String> _officialFixtureValidationErrors({
  required String benefitIssuer,
  required String benefitUrl,
  required String benefitCardName,
  required String discoveryIssuer,
  required String discoveryUrl,
  required String discoveryCardName,
  required String expectedNewProduct,
}) {
  final errors = <String>[];
  void requireText(String name, String value) {
    if (value.trim().length < 2) errors.add(name);
  }

  requireText('SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER', benefitIssuer);
  requireText('SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME', benefitCardName);
  requireText('SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER', discoveryIssuer);
  requireText(
    'SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_CARD_NAME',
    discoveryCardName,
  );
  requireText(
    'SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT',
    expectedNewProduct,
  );
  if (benefitIssuer.trim().isNotEmpty &&
      benefitIssuer.trim().toLowerCase() ==
          discoveryIssuer.trim().toLowerCase()) {
    errors.add('SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER');
  }
  if (!_isPublicHttpsFixtureUrl(benefitUrl)) {
    errors.add('SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL');
  }
  if (!_isPublicHttpsFixtureUrl(discoveryUrl)) {
    errors.add('SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL');
  }
  return errors;
}

Set<String> _addedIds(Set<String> before, Set<String> after) =>
    after.difference(before);

final _officialFixtureErrors = _officialFixtureValidationErrors(
  benefitIssuer: _officialBenefitIssuer,
  benefitUrl: _officialBenefitUrl,
  benefitCardName: _officialBenefitCardName,
  discoveryIssuer: _officialDiscoveryIssuer,
  discoveryUrl: _officialDiscoveryUrl,
  discoveryCardName: _officialDiscoveryCardName,
  expectedNewProduct: _officialDiscoveryExpectedNewProduct,
);

final _integrationSkipReason =
    localSupabaseSkipReason ??
    (_serviceRoleKey.isEmpty
        ? 'Requires SUPABASE_SERVICE_ROLE_KEY.'
        : !_isLoopbackUrl(localSupabaseUrl)
        ? 'Refuses non-loopback SUPABASE_URL.'
        : _officialFixtureErrors.isNotEmpty
        ? 'Requires complete public HTTPS official fixture configuration: '
              '${_officialFixtureErrors.join(', ')}.'
        : null);

bool _isLoopbackUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return uri.host == '127.0.0.1' ||
      uri.host == 'localhost' ||
      uri.host == '::1';
}

bool _isPublicHttpsFixtureUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
  if (uri.userInfo.isNotEmpty || _isLoopbackUrl(value)) return false;
  final host = uri.host.toLowerCase();
  final ipv4 = host.split('.').map(int.tryParse).toList(growable: false);
  if (ipv4.length == 4 && ipv4.every((part) => part != null)) {
    final first = ipv4[0]!;
    final second = ipv4[1]!;
    if (first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168)) {
      return false;
    }
  }
  return host != '0:0:0:0:0:0:0:1' &&
      host != '::' &&
      !host.startsWith('fc') &&
      !host.startsWith('fd') &&
      !RegExp(r'^fe[89ab]').hasMatch(host);
}

Map<String, dynamic> _row(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> _rows(dynamic value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList(growable: false);

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
  String parserVersion,
) async {
  final claimed = _rows(
    await service.rpc(
      'claim_card_catalog_enrichment_jobs',
      params: {
        '_max_jobs': 1,
        '_lease_seconds': 60,
        '_run_mode': 'manual',
        '_parser_version': parserVersion,
      },
    ),
  );
  expect(claimed, hasLength(1));
  expect(claimed.single['id'], expectedJobId);
  return claimed.single;
}

Future<Map<String, dynamic>> _callManualBatch() async {
  final endpoint = Uri.parse(
    '${localSupabaseUrl.replaceFirst(RegExp(r'/+$'), '')}'
    '/functions/v1/benefit-enrichment-batch',
  );
  final response = await http.post(
    endpoint,
    headers: {
      HttpHeaders.authorizationHeader: 'Bearer $_serviceRoleKey',
      'apikey': _serviceRoleKey,
      HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
    },
    body: jsonEncode({'run_mode': 'manual'}),
  );
  expect(response.statusCode, HttpStatus.ok, reason: response.body);
  final payload = _row(jsonDecode(response.body));
  expect(payload['error'], isNull, reason: response.body);
  return payload;
}

Future<Map<String, dynamic>> _readJob(
  SupabaseClient service,
  String jobId,
) async => _row(
  await service
      .from('card_catalog_enrichment_jobs')
      .select()
      .eq('id', jobId)
      .single(),
);

Future<Map<String, dynamic>> _waitForStagedJob(
  SupabaseClient service,
  String jobId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final job = await _readJob(service, jobId);
    if (job['status'] == 'staged' && job['staging_id'] != null) return job;
    if (job['status'] == 'failed' ||
        job['status'] == 'quarantined' ||
        job['status'] == 'review_required') {
      fail(
        'Batch job $jobId ended as ${job['status']}: '
        '${job['failure_category']}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for batch-produced staging for job $jobId.');
}

Future<Map<String, dynamic>> _readStaging(
  SupabaseClient service,
  String stagingId,
) async => _row(
  await service
      .from('card_benefits_staging')
      .select()
      .eq('id', stagingId)
      .single(),
);

Future<void> _requeueJob(SupabaseClient service, String jobId) async {
  await service
      .from('card_catalog_enrichment_jobs')
      .update({
        'status': 'queued',
        'staging_id': null,
        'content_hash': null,
        'lease_expires_at': null,
        'lease_token': null,
        'failure_category': null,
        'next_retry_at': null,
      })
      .eq('id', jobId);
}

Future<Set<String>> _tableIds(
  SupabaseClient service,
  String table,
  String idColumn,
) async {
  const pageSize = 1000;
  final ids = <String>{};
  for (var offset = 0; ; offset += pageSize) {
    final page = await service
        .from(table)
        .select(idColumn)
        .range(offset, offset + pageSize - 1);
    ids.addAll(
      (page as List).map((item) => (item as Map)[idColumn].toString()),
    );
    if (page.length < pageSize) return ids;
  }
}

String _normalizedProduct(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

bool _matchesExpectedProduct(String actual, String expected) {
  final normalizedActual = _normalizedProduct(actual);
  final normalizedExpected = _normalizedProduct(expected);
  return normalizedActual == normalizedExpected ||
      normalizedActual.contains(normalizedExpected) ||
      normalizedExpected.contains(normalizedActual);
}

Future<Map<String, dynamic>> _waitForCrawlerReview(
  SupabaseClient service, {
  required Set<String> baselineJobIds,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final rows = _rows(
      await service
          .from('card_discovery_jobs')
          .select('id,user_id,issuer,proposed_product,status,review_item_id')
          .eq('discovery_source', 'issuer_crawl')
          .eq('issuer', _officialDiscoveryIssuer),
    );
    for (final row in rows) {
      if (baselineJobIds.contains(row['id'])) continue;
      if (_matchesExpectedProduct(
        (row['proposed_product'] ?? '').toString(),
        _officialDiscoveryExpectedNewProduct,
      )) {
        if (row['status'] == 'review_required' &&
            row['review_item_id'] != null) {
          return row;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail(
    'Timed out waiting for function-produced review for '
    '$_officialDiscoveryExpectedNewProduct.',
  );
}

Map<String, dynamic> _firstAddition(Map<String, dynamic> staging) {
  final extracted = _row(staging['extracted_data']);
  final diff = _row(extracted['diff']);
  final additions = _rows(diff['additions']);
  expect(additions, isNotEmpty, reason: 'official fixture needs an addition');
  return additions.first;
}

void main() {
  test('official fixture contract requires complete public HTTPS products', () {
    expect(
      _officialFixtureValidationErrors(
        benefitIssuer: '',
        benefitUrl: 'http://127.0.0.1/fixture',
        benefitCardName: '',
        discoveryIssuer: 'Kotak Bank',
        discoveryUrl: 'https://localhost/card',
        discoveryCardName: 'Known discovery card',
        expectedNewProduct: '',
      ),
      containsAll(<String>[
        'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER',
        'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL',
        'SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME',
        'SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL',
        'SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT',
      ]),
    );
    expect(
      _officialFixtureValidationErrors(
        benefitIssuer: 'Axis Bank',
        benefitUrl: 'https://www.axis.bank.in/cards/fixture',
        benefitCardName: 'Known fixture card',
        discoveryIssuer: 'Kotak Bank',
        discoveryUrl: 'https://www.kotak.com/cards/fixture',
        discoveryCardName: 'Known discovery card',
        expectedNewProduct: 'New crawler card',
      ),
      isEmpty,
    );
    expect(
      _officialFixtureValidationErrors(
        benefitIssuer: 'Axis Bank',
        benefitUrl: 'https://www.axis.bank.in/cards/fixture-one',
        benefitCardName: 'Known fixture card',
        discoveryIssuer: ' axis bank ',
        discoveryUrl: 'https://www.axis.bank.in/cards/fixture-two',
        discoveryCardName: 'Known discovery card',
        expectedNewProduct: 'New crawler card',
      ),
      contains('SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER'),
    );
  });

  test('identity delta reports only newly created rows', () {
    expect(_addedIds({'a', 'b'}, {'a', 'b'}), isEmpty);
    expect(_addedIds({'a', 'b'}, {'a', 'b', 'c'}), {'c'});
  });

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
      String? knownCardId;
      String? discoveryCardId;
      String? reviewerId;
      String? approvedDedupeKey;
      String? createdApprovedBenefitId;
      final createdCrawlerJobIds = <String>{};
      Set<String>? baselineCrawlerJobIds;
      final existingDedupeKey = 'task10-existing-$suffix';
      final rejectedParserVersion = 'benefits-task10-reject-$suffix';
      final approvedParserVersion = 'benefits-task10-approve-$suffix';
      final discoveryParserVersion = 'benefits-task10-discovery-$suffix';

      try {
        expect(_officialFixtureErrors, isEmpty);

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
            'apikey': _serviceRoleKey,
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
                'bank': _officialBenefitIssuer,
                'card_name': _officialBenefitCardName,
                'card_type': 'credit',
                'card_url': _officialBenefitUrl,
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
        final existingMapping = _row(
          await service
              .from('card_benefit_mapping')
              .insert({
                'card_id': knownCardId,
                'benefit_id': existingBenefit['benefit_id'],
                'display_priority': 1,
                'is_primary': true,
                'category_codes': ['DINING'],
              })
              .select()
              .single(),
        );

        final existingDiscoveryCards = _rows(
          await service
              .from('card_catalog')
              .select('id,card_name')
              .eq('bank', _officialDiscoveryIssuer),
        );
        expect(
          existingDiscoveryCards.any(
            (row) => _matchesExpectedProduct(
              (row['card_name'] ?? '').toString(),
              _officialDiscoveryExpectedNewProduct,
            ),
          ),
          isFalse,
          reason: 'discovery fixture must represent a new catalog product',
        );
        baselineCrawlerJobIds = await _tableIds(
          service,
          'card_discovery_jobs',
          'id',
        );

        final rejectedJob = await _insertManualJob(
          service,
          cardId: knownCardId,
          issuer: _officialBenefitIssuer,
          sourceUrl: _officialBenefitUrl,
          parserVersion: rejectedParserVersion,
        );
        var claimedRejected = await _claimManualJob(
          service,
          rejectedJob['id'] as String,
          rejectedParserVersion,
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
          rejectedParserVersion,
        );
        expect(claimedRejected['attempt_count'], 2);
        expect(claimedRejected['lease_token'], isNot(firstLeaseToken));

        await service
            .from('card_catalog_enrichment_jobs')
            .update({
              'lease_expires_at': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            })
            .eq('id', rejectedJob['id']);
        final firstBatch = await _callManualBatch();
        expect(firstBatch['claimed'], 1);
        expect(firstBatch['staged'], 1);
        final firstProcessedJob = await _waitForStagedJob(
          service,
          rejectedJob['id'] as String,
        );
        expect(firstProcessedJob['status'], 'staged');
        final firstStagingId = firstProcessedJob['staging_id'] as String;
        final firstStage = await _readStaging(service, firstStagingId);
        expect(firstStage['status'], 'pending');
        expect(
          _isPublicHttpsFixtureUrl(firstStage['source_url'].toString()),
          isTrue,
        );
        final rejectedProposal = _firstAddition(firstStage);

        await _requeueJob(service, rejectedJob['id'] as String);
        final repeatedBatch = await _callManualBatch();
        expect(repeatedBatch['claimed'], 1);
        expect(repeatedBatch['staged'], 1);
        final repeatedJob = await _waitForStagedJob(
          service,
          rejectedJob['id'] as String,
        );
        expect(repeatedJob['staging_id'], firstStagingId);
        expect(_row(repeatedJob['result_summary'])['reused_staging'], isTrue);
        final oneStagingRow = await service
            .from('card_benefits_staging')
            .select('id')
            .eq('card_id', knownCardId)
            .eq('parser_version', rejectedParserVersion)
            .eq('content_hash', firstStage['content_hash']);
        expect(oneStagingRow, hasLength(1));

        final liveBenefitsBeforeReject = await _tableIds(
          service,
          'benefits',
          'benefit_id',
        );
        final liveMappingsBeforeReject = await _tableIds(
          service,
          'card_benefit_mapping',
          'mapping_id',
        );
        final rejection = _rows(
          await service.rpc(
            'approve_card_benefit_enrichment',
            params: {
              '_staging_id': firstStagingId,
              '_reviewed_by': reviewerId,
              '_decisions': [
                {
                  'action': 'reject',
                  'change_type': 'addition',
                  'dedupe_key': rejectedProposal['dedupeKey'],
                  'benefit': rejectedProposal,
                  'reason': 'Deterministic Task 10 rejection',
                },
              ],
            },
          ),
        );
        expect(rejection.single['resulting_status'], 'rejected');
        final liveBenefitsAfterReject = await _tableIds(
          service,
          'benefits',
          'benefit_id',
        );
        final liveMappingsAfterReject = await _tableIds(
          service,
          'card_benefit_mapping',
          'mapping_id',
        );
        expect(liveBenefitsAfterReject, liveBenefitsBeforeReject);
        expect(liveMappingsAfterReject, liveMappingsBeforeReject);
        expect(
          liveBenefitsAfterReject,
          contains(existingBenefit['benefit_id']),
        );
        expect(
          liveMappingsAfterReject,
          contains(existingMapping['mapping_id']),
        );

        final approvedJob = await _insertManualJob(
          service,
          cardId: knownCardId,
          issuer: _officialBenefitIssuer,
          sourceUrl: _officialBenefitUrl,
          parserVersion: approvedParserVersion,
        );
        final approvedBatch = await _callManualBatch();
        expect(approvedBatch['claimed'], 1);
        expect(approvedBatch['staged'], 1);
        final processedApprovedJob = await _waitForStagedJob(
          service,
          approvedJob['id'] as String,
        );
        expect(processedApprovedJob['status'], 'staged');
        final approvedStage = await _readStaging(
          service,
          processedApprovedJob['staging_id'] as String,
        );
        final approvedProposal = _firstAddition(approvedStage);
        approvedDedupeKey = approvedProposal['dedupeKey'].toString();
        final preexistingApprovedBenefit = await service
            .from('benefits')
            .select('benefit_id')
            .eq('dedupe_key', approvedDedupeKey);
        expect(
          preexistingApprovedBenefit,
          isEmpty,
          reason:
              'benefit fixture addition must be new to reset reference data',
        );
        final liveBenefitsBeforeApproval = await _tableIds(
          service,
          'benefits',
          'benefit_id',
        );
        final liveMappingsBeforeApproval = await _tableIds(
          service,
          'card_benefit_mapping',
          'mapping_id',
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
        final liveBenefitsAfterApproval = await _tableIds(
          service,
          'benefits',
          'benefit_id',
        );
        final liveMappingsAfterApproval = await _tableIds(
          service,
          'card_benefit_mapping',
          'mapping_id',
        );
        final newBenefitIds = _addedIds(
          liveBenefitsBeforeApproval,
          liveBenefitsAfterApproval,
        );
        final newMappingIds = _addedIds(
          liveMappingsBeforeApproval,
          liveMappingsAfterApproval,
        );
        expect(
          liveBenefitsAfterApproval.length,
          liveBenefitsBeforeApproval.length + 1,
        );
        expect(
          liveMappingsAfterApproval.length,
          liveMappingsBeforeApproval.length + 1,
        );
        expect(newBenefitIds, hasLength(1));
        expect(newMappingIds, hasLength(1));
        createdApprovedBenefitId = newBenefitIds.single;
        expect(
          liveBenefitsAfterApproval.intersection(liveBenefitsBeforeApproval),
          liveBenefitsBeforeApproval,
        );
        expect(
          liveMappingsAfterApproval.intersection(liveMappingsBeforeApproval),
          liveMappingsBeforeApproval,
        );
        final approvedBenefits = _rows(
          await service
              .from('benefits')
              .select('benefit_id,dedupe_key')
              .eq('dedupe_key', approvedDedupeKey),
        );
        expect(approvedBenefits, hasLength(1));
        expect(approvedBenefits.single['benefit_id'], newBenefitIds.single);
        final approvedMappings = _rows(
          await service
              .from('card_benefit_mapping')
              .select('mapping_id,card_id,benefit_id')
              .eq('card_id', knownCardId)
              .eq('benefit_id', approvedBenefits.single['benefit_id']),
        );
        expect(approvedMappings, hasLength(1));
        expect(approvedMappings.single['mapping_id'], newMappingIds.single);

        final discoveryCard = _row(
          await service
              .from('card_catalog')
              .insert({
                'bank': _officialDiscoveryIssuer,
                'card_name': _officialDiscoveryCardName,
                'card_type': 'credit',
                'card_url': _officialDiscoveryUrl,
                'is_discontinued': false,
              })
              .select()
              .single(),
        );
        discoveryCardId = discoveryCard['id'] as String;
        final discoveryJob = await _insertManualJob(
          service,
          cardId: discoveryCardId,
          issuer: _officialDiscoveryIssuer,
          sourceUrl: _officialDiscoveryUrl,
          parserVersion: discoveryParserVersion,
        );
        final discoveryBatch = await _callManualBatch();
        expect(discoveryBatch['claimed'], 1);
        expect(discoveryBatch['staged'], 1);
        await _waitForStagedJob(service, discoveryJob['id'] as String);
        final crawlerJob = await _waitForCrawlerReview(
          service,
          baselineJobIds: baselineCrawlerJobIds,
        );
        createdCrawlerJobIds.add(crawlerJob['id'] as String);
        expect(crawlerJob['user_id'], isNull);
        final crawlerReview = _row(
          await service
              .from('card_catalog_review_queue')
              .select('id,status,discovery_job_id')
              .eq('id', crawlerJob['review_item_id'])
              .single(),
        );
        expect(crawlerReview['status'], 'pending');
        expect(crawlerReview['discovery_job_id'], crawlerJob['id']);

        await service
            .from('card_catalog_review_queue')
            .delete()
            .eq('id', crawlerReview['id']);
        await _requeueJob(service, discoveryJob['id'] as String);
        final repeatedDiscoveryBatch = await _callManualBatch();
        expect(repeatedDiscoveryBatch['claimed'], 1);
        expect(repeatedDiscoveryBatch['staged'], 1);
        final repeatedDiscoveryJob = await _waitForStagedJob(
          service,
          discoveryJob['id'] as String,
        );
        expect(
          _row(repeatedDiscoveryJob['result_summary'])['reused_staging'],
          isTrue,
        );
        final repeatedCrawlerJob = await _waitForCrawlerReview(
          service,
          baselineJobIds: baselineCrawlerJobIds,
        );
        expect(repeatedCrawlerJob['id'], crawlerJob['id']);
        expect(
          repeatedCrawlerJob['review_item_id'],
          isNot(crawlerReview['id']),
        );
        final matchingCrawlerRows =
            _rows(
              await service
                  .from('card_discovery_jobs')
                  .select('id,proposed_product')
                  .eq('discovery_source', 'issuer_crawl')
                  .eq('issuer', _officialDiscoveryIssuer),
            ).where(
              (row) => _matchesExpectedProduct(
                (row['proposed_product'] ?? '').toString(),
                _officialDiscoveryExpectedNewProduct,
              ),
            );
        expect(matchingCrawlerRows.map((row) => row['id']).toSet(), {
          crawlerJob['id'],
        });
      } finally {
        if (baselineCrawlerJobIds != null) {
          final currentCrawlerJobIds = await _tableIds(
            service,
            'card_discovery_jobs',
            'id',
          );
          createdCrawlerJobIds.addAll(
            currentCrawlerJobIds.difference(baselineCrawlerJobIds),
          );
        }
        if (createdCrawlerJobIds.isNotEmpty) {
          await service
              .from('card_discovery_jobs')
              .delete()
              .inFilter('id', createdCrawlerJobIds.toList());
        }
        if (discoveryCardId != null) {
          await service.from('card_catalog').delete().eq('id', discoveryCardId);
        }
        if (knownCardId != null) {
          await service.from('card_catalog').delete().eq('id', knownCardId);
        }
        if (createdApprovedBenefitId != null) {
          await service
              .from('benefits')
              .delete()
              .eq('benefit_id', createdApprovedBenefitId);
        }
        await service
            .from('benefits')
            .delete()
            .eq('dedupe_key', existingDedupeKey);
        if (reviewerId != null) {
          await service.auth.admin.deleteUser(reviewerId);
        }
        service.dispose();
        anonymous.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 4)));
  }, skip: _integrationSkipReason);
}
