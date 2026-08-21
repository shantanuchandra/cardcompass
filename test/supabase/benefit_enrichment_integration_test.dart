// Guarded database/RPC/RLS verification against the one hosted CardCompass
// project. This file never calls or deploys Edge Functions and never crawls an
// issuer. The hosted group is skipped unless every exact-target prerequisite
// is supplied explicitly; pure safety-contract tests always run offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _expectedProjectRef = 'prbcoxqobhjnnfnxevxf';
const _expectedProjectName = 'cardcompass';
const _runHostedIntegration = bool.fromEnvironment(
  'RUN_HOSTED_CARD_INGESTION_INTEGRATION',
);
const _runHostedConcurrency = bool.fromEnvironment(
  'RUN_HOSTED_CARD_INGESTION_CONCURRENCY',
);
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _projectRef = String.fromEnvironment('SUPABASE_PROJECT_REF');
const _projectName = String.fromEnvironment('SUPABASE_PROJECT_NAME');
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
const _databaseUrl = String.fromEnvironment('CARD_INGESTION_DATABASE_URL');

final _pgpassFile = Platform.environment['PGPASSFILE'] ?? '';
final _psqlPath = Platform.environment['PSQL'] ?? 'psql';

class _PsqlSessionSpec {
  const _PsqlSessionSpec({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

List<String> _hostedConcurrencyConfigurationErrors({
  required bool runHostedConcurrency,
  required String databaseUrl,
  required String pgpassFile,
  required String psqlPath,
}) {
  final errors = <String>[];
  if (!runHostedConcurrency) {
    errors.add('RUN_HOSTED_CARD_INGESTION_CONCURRENCY=true');
  }
  final uri = Uri.tryParse(databaseUrl.trim());
  if (uri == null ||
      uri.scheme != 'postgresql' ||
      uri.host != 'aws-1-ap-south-1.pooler.supabase.com' ||
      uri.port != 6543 ||
      uri.path != '/postgres' ||
      uri.userInfo != 'postgres.$_expectedProjectRef' ||
      uri.queryParameters.length != 1 ||
      uri.queryParameters['sslmode'] != 'require' ||
      uri.hasFragment) {
    errors.add('password-free CARD_INGESTION_DATABASE_URL');
  }
  if (pgpassFile.trim().isEmpty) errors.add('PGPASSFILE');
  if (psqlPath.trim().isEmpty) errors.add('PSQL');
  return errors;
}

_PsqlSessionSpec _psqlSessionSpec({
  required String psqlPath,
  required String databaseUrl,
  required String pgpassFile,
  required String applicationName,
}) => _PsqlSessionSpec(
  executable: psqlPath,
  arguments: <String>[
    '-X',
    '--set',
    'ON_ERROR_STOP=1',
    '--no-psqlrc',
    databaseUrl,
  ],
  environment: <String, String>{
    'PGPASSFILE': pgpassFile,
    'PGAPPNAME': applicationName,
  },
);

List<String> _hostedConfigurationErrors({
  required bool runHostedIntegration,
  required String supabaseUrl,
  required String projectRef,
  required String projectName,
  required String anonKey,
  required String serviceRoleKey,
}) {
  final errors = <String>[];
  if (!runHostedIntegration) {
    errors.add('RUN_HOSTED_CARD_INGESTION_INTEGRATION=true');
  }
  final uri = Uri.tryParse(supabaseUrl.trim());
  final expectedHost = '$_expectedProjectRef.supabase.co';
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != expectedHost ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    errors.add('SUPABASE_URL');
  }
  if (projectRef.trim() != _expectedProjectRef) {
    errors.add('SUPABASE_PROJECT_REF=$_expectedProjectRef');
  }
  if (projectName.trim() != _expectedProjectName) {
    errors.add('SUPABASE_PROJECT_NAME=$_expectedProjectName');
  }
  if (anonKey.trim().isEmpty) errors.add('SUPABASE_ANON_KEY');
  if (serviceRoleKey.trim().isEmpty) {
    errors.add('SUPABASE_SERVICE_ROLE_KEY');
  }
  if (anonKey.trim().isNotEmpty && anonKey == serviceRoleKey) {
    errors.add('distinct anon and service-role keys');
  }
  return errors;
}

final _hostedConfigurationErrorList = _hostedConfigurationErrors(
  runHostedIntegration: _runHostedIntegration,
  supabaseUrl: _supabaseUrl,
  projectRef: _projectRef,
  projectName: _projectName,
  anonKey: _anonKey,
  serviceRoleKey: _serviceRoleKey,
);

final _hostedConcurrencyConfigurationErrorList = <String>[
  ..._hostedConfigurationErrorList,
  ..._hostedConcurrencyConfigurationErrors(
    runHostedConcurrency: _runHostedConcurrency,
    databaseUrl: _databaseUrl,
    pgpassFile: _pgpassFile,
    psqlPath: _psqlPath,
  ),
];

final _hostedConcurrencySkipReason =
    _hostedConcurrencyConfigurationErrorList.isEmpty
    ? null
    : 'Requires exact guarded hosted concurrency configuration: '
          '${_hostedConcurrencyConfigurationErrorList.join(', ')}.';

String _sqlLiteral(String value) {
  if (!RegExp(r'^[a-zA-Z0-9:_-]{1,240}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'value', 'is not a safe lock identity');
  }
  return value;
}

Future<T> _runBehindRolledBackAdvisoryLock<T>({
  required String lockIdentity,
  required Future<T> Function() operation,
}) async {
  final pgpass = File(_pgpassFile);
  final stat = await pgpass.stat();
  if (stat.type != FileSystemEntityType.file || (stat.mode & 0x3f) != 0) {
    throw StateError('PGPASSFILE must be a mode-0600 regular file');
  }
  final spec = _psqlSessionSpec(
    psqlPath: _psqlPath,
    databaseUrl: _databaseUrl,
    pgpassFile: _pgpassFile,
    applicationName: 'task11-concurrency-lock-holder',
  );
  final process = await Process.start(
    spec.executable,
    spec.arguments,
    environment: <String, String>{...Platform.environment, ...spec.environment},
  );
  final stdoutLines = <String>[];
  final stderrLines = <String>[];
  final acquired = Completer<void>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      stdoutLines.add(line);
      if (line.trim() == 'TASK11_LOCK_ACQUIRED' && !acquired.isCompleted) {
        acquired.complete();
      }
    },
  );
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderrLines.add);
  process.stdin.write('''
BEGIN;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '10s';
SELECT pg_advisory_xact_lock(hashtextextended('${_sqlLiteral(lockIdentity)}', 0));
\\echo TASK11_LOCK_ACQUIRED
''');
  await process.stdin.flush();
  await acquired.future.timeout(const Duration(seconds: 20));
  final pending = operation();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  process.stdin.write('ROLLBACK;\n\\q\n');
  await process.stdin.flush();
  await process.stdin.close();
  final exitCode = await process.exitCode.timeout(const Duration(seconds: 20));
  if (exitCode != 0) {
    throw StateError(
      'lock-holder psql failed ($exitCode): ${stderrLines.join(' | ')}; '
      'stdout=${stdoutLines.join(' | ')}',
    );
  }
  return pending.timeout(const Duration(seconds: 30));
}

Future<void> _runCatalogPublicationRollbackProbe({
  required String discoveryJobId,
  required String reviewItemId,
  required String actorId,
}) async {
  final spec = _psqlSessionSpec(
    psqlPath: _psqlPath,
    databaseUrl: _databaseUrl,
    pgpassFile: _pgpassFile,
    applicationName: 'task11-publication-rollback-probe',
  );
  final process = await Process.start(
    spec.executable,
    spec.arguments,
    environment: <String, String>{...Platform.environment, ...spec.environment},
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.write('''
\\set VERBOSITY verbose
BEGIN;
SET LOCAL statement_timeout = '30s';
SELECT * FROM public.publish_card_catalog_identity(
  '${_sqlLiteral(discoveryJobId)}'::uuid,
  '${_sqlLiteral(reviewItemId)}'::uuid,
  '${_sqlLiteral(actorId)}'::uuid,
  'edit_approve', '{}'::jsonb, NULL, NULL, 'benefits-v6'
);
ROLLBACK;
''');
  await process.stdin.close();
  final exitCode = await process.exitCode.timeout(const Duration(seconds: 40));
  final stdoutText = await stdoutFuture;
  final stderrText = await stderrFuture;
  if (exitCode != 0) {
    throw StateError(
      'publication rollback probe failed ($exitCode): $stderrText; '
      'stdout=$stdoutText',
    );
  }
}

String _buildRunId(DateTime now, List<int> entropy) {
  if (entropy.length != 16 || entropy.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError.value(entropy, 'entropy', 'must be exactly 16 bytes');
  }
  final utc = now.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  String six(int value) =>
      '${three(value ~/ 1000)}${three(value.remainder(1000))}';
  final timestamp =
      '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}t${two(utc.hour)}${two(utc.minute)}'
      '${two(utc.second)}${six(utc.millisecond * 1000 + utc.microsecond)}z';
  final random = entropy
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$timestamp-$random';
}

String _newRunId() {
  final random = Random.secure();
  return _buildRunId(
    DateTime.now().toUtc(),
    List<int>.generate(16, (_) => random.nextInt(256), growable: false),
  );
}

enum _FixtureTable {
  cardBenefitMapping('card_benefit_mapping', 'mapping_id'),
  cardCatalogEnrichmentJobs('card_catalog_enrichment_jobs', 'id'),
  cardBenefitsStaging('card_benefits_staging', 'id'),
  cardCatalogReviewAudit('card_catalog_review_audit', 'id'),
  cardCatalogReviewQueue('card_catalog_review_queue', 'id'),
  cardDiscoveryJobs('card_discovery_jobs', 'id'),
  users('users', 'id'),
  cardCatalogProvenance('card_catalog_provenance', 'id'),
  cardCatalogUrlKeys('card_catalog_url_keys', 'url_hash'),
  benefits('benefits', 'benefit_id'),
  cardCatalog('card_catalog', 'id');

  const _FixtureTable(this.databaseName, this.idColumn);

  final String databaseName;
  final String idColumn;
}

class _CleanupTarget {
  const _CleanupTarget(this.table, this.ids);

  final _FixtureTable table;
  final Set<String> ids;
}

class _CleanupStep {
  const _CleanupStep(this.label, this.run);

  final String label;
  final Future<void> Function() run;
}

class _CleanupFailure {
  const _CleanupFailure(this.label, this.error, this.stackTrace);

  final String label;
  final Object error;
  final StackTrace stackTrace;
}

class _CleanupException implements Exception {
  const _CleanupException(this.failures);

  final List<_CleanupFailure> failures;

  @override
  String toString() =>
      'Hosted fixture cleanup failed: ${failures.map((failure) => '${failure.label}: ${failure.error}').join('; ')}';
}

class _AsyncOutcome<T> {
  const _AsyncOutcome.value(this.value) : error = null;
  const _AsyncOutcome.error(this.error) : value = null;

  final T? value;
  final Object? error;

  bool get succeeded => error == null;
}

Future<_AsyncOutcome<T>> _captureOutcome<T>(Future<T> operation) async {
  try {
    return _AsyncOutcome<T>.value(await operation);
  } catch (error) {
    return _AsyncOutcome<T>.error(error);
  }
}

Future<void> _runCleanupSteps(List<_CleanupStep> steps) async {
  final failures = <_CleanupFailure>[];
  for (final step in steps) {
    try {
      await step.run();
    } catch (error, stackTrace) {
      failures.add(_CleanupFailure(step.label, error, stackTrace));
    }
  }
  if (failures.isNotEmpty) {
    throw _CleanupException(List<_CleanupFailure>.unmodifiable(failures));
  }
}

class _FixtureLedger {
  _FixtureLedger(this.runId);

  final String runId;
  final Map<_FixtureTable, Set<String>> _ids = <_FixtureTable, Set<String>>{};
  final Set<String> authUserIds = <String>{};
  bool _markerRecoveryAllowed = false;

  bool get markerRecoveryAllowed => _markerRecoveryAllowed;

  void allowMarkerRecoveryAfterClearPreflight() {
    _markerRecoveryAllowed = true;
  }

  void record(_FixtureTable table, String id) {
    final exactId = id.trim();
    if (exactId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    (_ids[table] ??= <String>{}).add(exactId);
  }

  Set<String> idsFor(_FixtureTable table) =>
      Set<String>.unmodifiable(_ids[table] ?? const <String>{});

  List<_CleanupTarget> get cleanupTargets => <_CleanupTarget>[
    for (final table in _FixtureTable.values)
      if ((_ids[table] ?? const <String>{}).isNotEmpty)
        _CleanupTarget(table, Set<String>.unmodifiable(_ids[table]!)),
  ];
}

class _RunFixture {
  _RunFixture(this.runId)
    : issuer = 'Axis Bank',
      cardName = 'Task11 hosted Visa DB RPC $runId',
      sourceUrl = 'https://www.axis.bank.in/task11/$runId',
      benefitDedupeKey = 'task11-hosted-benefit:$runId',
      proposalDedupeKey = 'task11-hosted-proposal:$runId',
      identityDedupeKey = 'task11-page-move:$runId',
      quarantineAnchorDedupeKey = 'task11-quarantine-anchor:$runId',
      quarantineReviewDedupeKey = 'task11-quarantine-review:$runId:1',
      claimParserVersion = 'task11-harness-${_sha256(runId).substring(0, 24)}',
      reviewerEmail = 'ci-${_sha256(runId).substring(0, 32)}@example.com',
      reviewerCredential = '${_sha256('auth:$runId')}Aa1!';

  final String runId;
  final String issuer;
  final String cardName;
  final String sourceUrl;
  final String benefitDedupeKey;
  final String proposalDedupeKey;
  final String identityDedupeKey;
  final String quarantineAnchorDedupeKey;
  final String quarantineReviewDedupeKey;
  final String claimParserVersion;
  final String reviewerEmail;
  final String reviewerCredential;

  String get sourceUrlHash => _sha256(sourceUrl);
  String get contentHash => _sha256('content:$runId');
  String get movedSourceUrl => '$sourceUrl?variant=concurrency';
  String get movedSourceUrlHash => _sha256(movedSourceUrl);
  String get identitySemanticHash => _sha256('page-move:$runId');
  List<String> get discoveryDedupeKeys => <String>[
    identityDedupeKey,
    quarantineAnchorDedupeKey,
    quarantineReviewDedupeKey,
    quarantineReviewDedupeKeyFor(2),
  ];
  String quarantineReviewDedupeKeyFor(int episode) =>
      'task11-quarantine-review:$runId:$episode';
}

class _AuthIdentity {
  const _AuthIdentity(this.id, this.email);

  final String id;
  final String? email;
}

typedef _AuthPageLoader =
    Future<List<_AuthIdentity>> Function(int page, int perPage);

Future<Set<String>> _findExactAuthUserIds({
  required String expectedEmail,
  required _AuthPageLoader loadPage,
  int perPage = 100,
  int maxPages = 100,
}) async {
  final normalizedEmail = expectedEmail.trim().toLowerCase();
  if (normalizedEmail.isEmpty ||
      perPage < 1 ||
      perPage > 1000 ||
      maxPages < 1 ||
      maxPages > 1000) {
    throw ArgumentError('invalid bounded auth lookup');
  }
  final matches = <String>{};
  for (var page = 1; page <= maxPages; page++) {
    final identities = await loadPage(page, perPage);
    if (identities.length > perPage) {
      throw StateError('auth page exceeded requested bound');
    }
    for (final identity in identities) {
      if (identity.email?.trim().toLowerCase() == normalizedEmail) {
        final exactId = identity.id.trim();
        if (exactId.isEmpty) throw StateError('auth identity has no ID');
        matches.add(exactId);
      }
    }
    if (identities.length < perPage) return matches;
  }
  throw StateError('auth lookup page bound exhausted');
}

Future<Set<String>> _hostedAuthUserIdsForEmail(
  SupabaseClient service,
  String email,
) => _findExactAuthUserIds(
  expectedEmail: email,
  loadPage: (page, perPage) async {
    final users = await service.auth.admin.listUsers(
      page: page,
      perPage: perPage,
    );
    return users
        .map((user) => _AuthIdentity(user.id, user.email))
        .toList(growable: false);
  },
);

Map<String, dynamic> _row(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> _rows(dynamic value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList(growable: false);

typedef _BenefitRowsByDedupeKey =
    Future<List<Map<String, dynamic>>> Function(String dedupeKey);

List<String> _benefitDedupeKeys(_RunFixture fixture) =>
    List<String>.unmodifiable(<String>[
      fixture.benefitDedupeKey,
      fixture.proposalDedupeKey,
    ]);

Future<void> _assertNoBenefitDedupeCollision(
  _RunFixture fixture, {
  required _BenefitRowsByDedupeKey loadByDedupeKey,
}) async {
  final occupiedKeys = <String>[];
  for (final dedupeKey in _benefitDedupeKeys(fixture)) {
    if ((await loadByDedupeKey(dedupeKey)).isNotEmpty) {
      occupiedKeys.add(dedupeKey);
    }
  }
  if (occupiedKeys.isNotEmpty) {
    throw StateError(
      'run benefit dedupe marker collision: ${occupiedKeys.join(', ')}',
    );
  }
}

Future<void> _recoverExactBenefitIds(
  _RunFixture fixture,
  _FixtureLedger ledger, {
  required _BenefitRowsByDedupeKey loadByDedupeKey,
}) async {
  if (!ledger.markerRecoveryAllowed) {
    throw StateError('run markers were not cleared for benefit recovery');
  }
  for (final dedupeKey in _benefitDedupeKeys(fixture)) {
    for (final benefit in await loadByDedupeKey(dedupeKey)) {
      ledger.record(_FixtureTable.benefits, benefit['benefit_id'].toString());
    }
  }
}

Future<void> _assertNoBenefitDedupeResiduals(
  _RunFixture fixture, {
  required _BenefitRowsByDedupeKey loadByDedupeKey,
}) async {
  final residualKeys = <String>[];
  for (final dedupeKey in _benefitDedupeKeys(fixture)) {
    if ((await loadByDedupeKey(dedupeKey)).isNotEmpty) {
      residualKeys.add(dedupeKey);
    }
  }
  if (residualKeys.isNotEmpty) {
    throw StateError(
      'run benefit dedupe marker retained: ${residualKeys.join(', ')}',
    );
  }
}

Future<void> _expectPermissionDenied(
  Future<dynamic> Function() operation, {
  required String reason,
}) async {
  try {
    await operation();
    fail(reason);
  } on PostgrestException catch (error) {
    expect(
      error.code,
      anyOf('42501', 'PGRST202'),
      reason: '$reason (${error.message})',
    );
  }
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

Future<List<Map<String, dynamic>>> _selectExact(
  SupabaseClient service,
  _FixtureTable table,
  Iterable<String> ids,
) async {
  final exactIds = ids.toSet().toList(growable: false);
  if (exactIds.isEmpty) return const <Map<String, dynamic>>[];
  return _rows(
    await service
        .from(table.databaseName)
        .select(table.idColumn)
        .inFilter(table.idColumn, exactIds),
  );
}

Future<List<Map<String, dynamic>>> _selectBenefitsByDedupeKey(
  SupabaseClient service,
  String dedupeKey,
) async => _rows(
  await service
      .from('benefits')
      .select('benefit_id')
      .eq('dedupe_key', dedupeKey),
);

Future<void> _assertNoMarkerCollision(
  SupabaseClient service,
  _RunFixture fixture,
) async {
  await _assertNoBenefitDedupeCollision(
    fixture,
    loadByDedupeKey: (dedupeKey) =>
        _selectBenefitsByDedupeKey(service, dedupeKey),
  );
  final collisions = <String, List<Map<String, dynamic>>>{
    'card_catalog': _rows(
      await service
          .from('card_catalog')
          .select('id')
          .eq('card_name', fixture.cardName)
          .eq('bank', fixture.issuer),
    ),
    'card_catalog_enrichment_jobs': _rows(
      await service
          .from('card_catalog_enrichment_jobs')
          .select('id')
          .eq('canonical_url', fixture.sourceUrl)
          .eq('issuer', fixture.issuer),
    ),
    'claim_parser_version': _rows(
      await service
          .from('card_catalog_enrichment_jobs')
          .select('id')
          .eq('parser_version', fixture.claimParserVersion)
          .limit(1),
    ),
    'card_benefits_staging': _rows(
      await service
          .from('card_benefits_staging')
          .select('id')
          .eq('source_url', fixture.sourceUrl)
          .eq('content_hash', fixture.contentHash),
    ),
    'card_catalog_url_keys': _rows(
      await service.from('card_catalog_url_keys').select('url_hash').inFilter(
        'url_hash',
        <String>[fixture.sourceUrlHash, fixture.movedSourceUrlHash],
      ),
    ),
    'card_discovery_jobs': _rows(
      await service
          .from('card_discovery_jobs')
          .select('id')
          .inFilter('dedupe_key', fixture.discoveryDedupeKeys),
    ),
  };
  final occupied = collisions.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => entry.key)
      .toList(growable: false);
  if (occupied.isNotEmpty) {
    throw StateError('run marker collision: ${occupied.join(', ')}');
  }
}

Future<void> _recoverExactCreatedIds(
  SupabaseClient service,
  _RunFixture fixture,
  _FixtureLedger ledger,
) async {
  if (!ledger.markerRecoveryAllowed) {
    throw StateError('run markers were not cleared for recovery');
  }
  ledger.authUserIds.addAll(
    await _hostedAuthUserIdsForEmail(service, fixture.reviewerEmail),
  );
  for (final authUserId in ledger.authUserIds) {
    final profileRows = _rows(
      await service.from('users').select('id').eq('id', authUserId),
    );
    for (final profile in profileRows) {
      ledger.record(_FixtureTable.users, profile['id'].toString());
    }
  }
  final cards = _rows(
    await service
        .from('card_catalog')
        .select('id')
        .eq('card_name', fixture.cardName)
        .eq('bank', fixture.issuer),
  );
  for (final card in cards) {
    ledger.record(_FixtureTable.cardCatalog, card['id'].toString());
  }
  await _recoverExactBenefitIds(
    fixture,
    ledger,
    loadByDedupeKey: (dedupeKey) =>
        _selectBenefitsByDedupeKey(service, dedupeKey),
  );
  final jobs = _rows(
    await service
        .from('card_catalog_enrichment_jobs')
        .select('id')
        .eq('canonical_url', fixture.sourceUrl)
        .eq('issuer', fixture.issuer),
  );
  for (final job in jobs) {
    ledger.record(
      _FixtureTable.cardCatalogEnrichmentJobs,
      job['id'].toString(),
    );
  }
  if (ledger.idsFor(_FixtureTable.cardCatalog).isNotEmpty) {
    final cardJobs = _rows(
      await service
          .from('card_catalog_enrichment_jobs')
          .select('id')
          .inFilter(
            'card_id',
            ledger.idsFor(_FixtureTable.cardCatalog).toList(growable: false),
          ),
    );
    for (final job in cardJobs) {
      ledger.record(
        _FixtureTable.cardCatalogEnrichmentJobs,
        job['id'].toString(),
      );
    }
  }
  final stagingRows = _rows(
    await service
        .from('card_benefits_staging')
        .select('id')
        .eq('source_url', fixture.sourceUrl)
        .eq('content_hash', fixture.contentHash),
  );
  for (final staging in stagingRows) {
    ledger.record(_FixtureTable.cardBenefitsStaging, staging['id'].toString());
  }
  final discoveryJobs = _rows(
    await service
        .from('card_discovery_jobs')
        .select('id')
        .inFilter('dedupe_key', fixture.discoveryDedupeKeys),
  );
  for (final job in discoveryJobs) {
    ledger.record(_FixtureTable.cardDiscoveryJobs, job['id'].toString());
  }
  final discoveryJobIds = ledger.idsFor(_FixtureTable.cardDiscoveryJobs);
  if (discoveryJobIds.isNotEmpty) {
    final reviews = _rows(
      await service
          .from('card_catalog_review_queue')
          .select('id')
          .inFilter(
            'discovery_job_id',
            discoveryJobIds.toList(growable: false),
          ),
    );
    for (final review in reviews) {
      ledger.record(
        _FixtureTable.cardCatalogReviewQueue,
        review['id'].toString(),
      );
    }
  }
  final reviewIds = ledger.idsFor(_FixtureTable.cardCatalogReviewQueue);
  if (reviewIds.isNotEmpty) {
    final audits = _rows(
      await service
          .from('card_catalog_review_audit')
          .select('id')
          .inFilter('review_item_id', reviewIds.toList(growable: false)),
    );
    for (final audit in audits) {
      ledger.record(
        _FixtureTable.cardCatalogReviewAudit,
        audit['id'].toString(),
      );
    }
  }
  final cardIds = ledger.idsFor(_FixtureTable.cardCatalog);
  if (cardIds.isNotEmpty) {
    final mappings = _rows(
      await service
          .from('card_benefit_mapping')
          .select('mapping_id')
          .inFilter('card_id', cardIds.toList(growable: false)),
    );
    for (final mapping in mappings) {
      ledger.record(
        _FixtureTable.cardBenefitMapping,
        mapping['mapping_id'].toString(),
      );
    }
    final provenance = _rows(
      await service
          .from('card_catalog_provenance')
          .select('id')
          .inFilter('card_id', cardIds.toList(growable: false)),
    );
    for (final row in provenance) {
      ledger.record(_FixtureTable.cardCatalogProvenance, row['id'].toString());
    }
  }
  final urlKeys = _rows(
    await service
        .from('card_catalog_url_keys')
        .select('url_hash,card_id')
        .inFilter('url_hash', <String>[
          fixture.sourceUrlHash,
          fixture.movedSourceUrlHash,
        ]),
  );
  for (final urlKey in urlKeys) {
    if (!cardIds.contains(urlKey['card_id'].toString())) {
      throw StateError('run URL hash is owned by another card');
    }
    ledger.record(
      _FixtureTable.cardCatalogUrlKeys,
      urlKey['url_hash'].toString(),
    );
  }
}

Future<void> _deleteRecordedTable(
  SupabaseClient service,
  _FixtureLedger ledger,
  _FixtureTable table,
) async {
  final exactIds = ledger.idsFor(table);
  if (exactIds.isEmpty) return;
  await service
      .from(table.databaseName)
      .delete()
      .inFilter(table.idColumn, exactIds.toList(growable: false));
}

Future<void> _verifyZeroResidualRows(
  SupabaseClient service,
  _RunFixture fixture,
  _FixtureLedger ledger,
) async {
  for (final table in _FixtureTable.values) {
    final remaining = await _selectExact(service, table, ledger.idsFor(table));
    expect(
      remaining,
      isEmpty,
      reason: '${table.databaseName} retained run IDs',
    );
  }
  expect(
    await service
        .from('card_catalog')
        .select('id')
        .eq('card_name', fixture.cardName)
        .eq('bank', fixture.issuer),
    isEmpty,
  );
  await _assertNoBenefitDedupeResiduals(
    fixture,
    loadByDedupeKey: (dedupeKey) =>
        _selectBenefitsByDedupeKey(service, dedupeKey),
  );
  expect(
    await service
        .from('card_catalog_enrichment_jobs')
        .select('id')
        .eq('canonical_url', fixture.sourceUrl)
        .eq('issuer', fixture.issuer),
    isEmpty,
  );
  expect(
    await service
        .from('card_benefits_staging')
        .select('id')
        .eq('source_url', fixture.sourceUrl)
        .eq('content_hash', fixture.contentHash),
    isEmpty,
  );
  expect(
    await service.from('card_catalog_url_keys').select('url_hash').inFilter(
      'url_hash',
      <String>[fixture.sourceUrlHash, fixture.movedSourceUrlHash],
    ),
    isEmpty,
  );
  expect(
    await service
        .from('card_discovery_jobs')
        .select('id')
        .inFilter('dedupe_key', fixture.discoveryDedupeKeys),
    isEmpty,
  );
  for (final authUserId in ledger.authUserIds) {
    expect(
      await service.from('users').select('id').eq('id', authUserId),
      isEmpty,
      reason: 'public.users retained auth fixture $authUserId',
    );
  }
  expect(
    await _hostedAuthUserIdsForEmail(service, fixture.reviewerEmail),
    isEmpty,
    reason: 'Supabase Auth retained ${fixture.reviewerEmail}',
  );
}

Map<String, dynamic> _claimParameters(_RunFixture fixture) => <String, dynamic>{
  '_max_jobs': 1,
  '_lease_seconds': 60,
  '_run_mode': 'manual',
  '_parser_version': fixture.claimParserVersion,
};

Map<String, dynamic> _proposal(_RunFixture fixture) => <String, dynamic>{
  'title': 'Hosted harness dining benefit',
  'description': 'Run-scoped terms used only for hosted database verification.',
  'category': 'DINING',
  'valueType': 'percent_discount',
  'rate': 10,
  'valueConfig': <String, dynamic>{'discount_percent': 10},
  'partners': <dynamic>[],
  'restrictions': <dynamic>[],
  'exclusions': <dynamic>[],
  'regions': <dynamic>['IN'],
  'dedupeKey': fixture.proposalDedupeKey,
  'sourceUrl': fixture.sourceUrl,
  'sourceExcerpt': '10 percent dining fixture for ${fixture.runId}',
  'contentHash': fixture.contentHash,
  'parserVersion': 'benefits-v5',
  'confidence': <String, dynamic>{'overall': 0.99},
  'evidence': <String, dynamic>{'run_id': fixture.runId},
  'warnings': <dynamic>[],
};

Map<String, dynamic> _pageMoveProposal({
  required _RunFixture fixture,
  required String cardId,
  required String updatedAt,
}) => <String, dynamic>{
  'issuer': fixture.issuer,
  'cardName': fixture.cardName,
  'network': 'Visa',
  'official_url': fixture.movedSourceUrl,
  'submitted_url': fixture.movedSourceUrl,
  'final_url': fixture.movedSourceUrl,
  'submitted_url_hash': fixture.movedSourceUrlHash,
  'final_url_hash': fixture.movedSourceUrlHash,
  'submitted_resource_identity_hash': fixture.movedSourceUrlHash,
  'final_resource_identity_hash': fixture.movedSourceUrlHash,
  'content_hash': fixture.contentHash,
  'retrieved_at': updatedAt,
  'source_status': 200,
  'source_type': 'official_html',
  'confidence': 0.99,
  'validation_version': 'card-identity-v3',
  'card_id': cardId,
  'catalog_baseline': <String, dynamic>{
    'card_id': cardId,
    'card_name': fixture.cardName,
    'network': 'Visa',
    'annual_fee': null,
    'joining_fee': null,
    'apr': null,
    'card_url': fixture.sourceUrl,
    'is_discontinued': false,
    'updated_at': updatedAt,
  },
};

Map<String, dynamic> _quarantineSourceObservation({
  required String anchorJobId,
  required String issuer,
  required int episode,
}) => <String, dynamic>{
  'anchor_job_id': anchorJobId,
  'classification': 'issuer_discovery_quarantine',
  'episode_identity': 'issuer-discovery-quarantine-v1:$anchorJobId:$episode',
  'issuer': issuer,
  'kind': 'issuer_discovery_quarantine',
  'reason': 'resume_attempts_exhausted',
  'retryable': true,
  'retryability_reason': 'attempt_budget_reset_allowed',
};

void main() {
  test('hosted configuration requires explicit exact cardcompass target', () {
    expect(
      _hostedConfigurationErrors(
        runHostedIntegration: false,
        supabaseUrl: 'https://prbcoxqobhjnnfnxevxf.supabase.co',
        projectRef: 'prbcoxqobhjnnfnxevxf',
        projectName: 'cardcompass',
        anonKey: 'anon-key',
        serviceRoleKey: 'service-role-key',
      ),
      contains('RUN_HOSTED_CARD_INGESTION_INTEGRATION=true'),
    );
    expect(
      _hostedConfigurationErrors(
        runHostedIntegration: true,
        supabaseUrl: 'https://another-project.supabase.co',
        projectRef: 'prbcoxqobhjnnfnxevxf',
        projectName: 'cardcompass',
        anonKey: 'anon-key',
        serviceRoleKey: 'service-role-key',
      ),
      contains('SUPABASE_URL'),
    );
    expect(
      _hostedConfigurationErrors(
        runHostedIntegration: true,
        supabaseUrl: 'https://prbcoxqobhjnnfnxevxf.supabase.co',
        projectRef: 'prbcoxqobhjnnfnxevxf',
        projectName: 'cardcompass',
        anonKey: 'anon-key',
        serviceRoleKey: 'service-role-key',
      ),
      isEmpty,
    );
    expect(
      _hostedConfigurationErrors(
        runHostedIntegration: true,
        supabaseUrl:
            'https://user@prbcoxqobhjnnfnxevxf.supabase.co:443/path?query=1#fragment',
        projectRef: 'wrong-ref',
        projectName: 'wrong-name',
        anonKey: 'same-key',
        serviceRoleKey: 'same-key',
      ),
      containsAll(<String>[
        'SUPABASE_URL',
        'SUPABASE_PROJECT_REF=prbcoxqobhjnnfnxevxf',
        'SUPABASE_PROJECT_NAME=cardcompass',
        'distinct anon and service-role keys',
      ]),
    );
  });

  test('hosted concurrency configuration requires password-free exact pooler', () {
    expect(
      _hostedConcurrencyConfigurationErrors(
        runHostedConcurrency: false,
        databaseUrl:
            'postgresql://postgres.prbcoxqobhjnnfnxevxf@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?sslmode=require',
        pgpassFile: '/tmp/task11.pgpass',
        psqlPath: '/opt/homebrew/opt/postgresql@17/bin/psql',
      ),
      contains('RUN_HOSTED_CARD_INGESTION_CONCURRENCY=true'),
    );
    expect(
      _hostedConcurrencyConfigurationErrors(
        runHostedConcurrency: true,
        databaseUrl:
            'postgresql://postgres.prbcoxqobhjnnfnxevxf:secret@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?sslmode=require',
        pgpassFile: '/tmp/task11.pgpass',
        psqlPath: '/opt/homebrew/opt/postgresql@17/bin/psql',
      ),
      contains('password-free CARD_INGESTION_DATABASE_URL'),
    );
    expect(
      _hostedConcurrencyConfigurationErrors(
        runHostedConcurrency: true,
        databaseUrl:
            'postgresql://postgres.prbcoxqobhjnnfnxevxf@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?sslmode=require',
        pgpassFile: '/tmp/task11.pgpass',
        psqlPath: '/opt/homebrew/opt/postgresql@17/bin/psql',
      ),
      isEmpty,
    );
  });

  test('two-session psql spec keeps credentials out of process arguments', () {
    final spec = _psqlSessionSpec(
      psqlPath: '/opt/homebrew/opt/postgresql@17/bin/psql',
      databaseUrl:
          'postgresql://postgres.prbcoxqobhjnnfnxevxf@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?sslmode=require',
      pgpassFile: '/tmp/task11.pgpass',
      applicationName: 'task11-concurrency-lock-holder',
    );
    expect(spec.executable, '/opt/homebrew/opt/postgresql@17/bin/psql');
    expect(spec.arguments.join(' '), isNot(contains('secret')));
    expect(spec.arguments, contains('-X'));
    expect(spec.environment, <String, String>{
      'PGPASSFILE': '/tmp/task11.pgpass',
      'PGAPPNAME': 'task11-concurrency-lock-holder',
    });
  });

  test(
    'page-move proposal binds the exact old catalog snapshot and new URL',
    () {
      final fixture = _RunFixture(
        '20260821t010203456789z-000102030405060708090a0b0c0d0e0f',
      );
      final proposal = _pageMoveProposal(
        fixture: fixture,
        cardId: '00000000-0000-4000-8000-000000000001',
        updatedAt: '2026-08-21T01:02:03.000Z',
      );
      expect(proposal['official_url'], fixture.movedSourceUrl);
      expect(proposal['submitted_url_hash'], fixture.movedSourceUrlHash);
      expect(proposal['final_url_hash'], fixture.movedSourceUrlHash);
      expect(proposal['card_id'], '00000000-0000-4000-8000-000000000001');
      expect(
        Map<String, dynamic>.from(proposal['catalog_baseline'] as Map),
        containsPair('card_url', fixture.sourceUrl),
      );
    },
  );

  test('quarantine episode binds one anchor and one immutable episode', () {
    final observation = _quarantineSourceObservation(
      anchorJobId: '00000000-0000-4000-8000-000000000002',
      issuer: 'Axis Bank',
      episode: 1,
    );
    expect(observation['classification'], 'issuer_discovery_quarantine');
    expect(observation['reason'], 'resume_attempts_exhausted');
    expect(observation['retryable'], isTrue);
    expect(
      observation['episode_identity'],
      'issuer-discovery-quarantine-v1:'
      '00000000-0000-4000-8000-000000000002:1',
    );
  });

  test('run ids require fresh entropy and stay safe in fixture markers', () {
    final first = _buildRunId(
      DateTime.utc(2026, 8, 21, 1, 2, 3, 456, 789),
      List<int>.generate(16, (index) => index),
    );
    final second = _buildRunId(
      DateTime.utc(2026, 8, 21, 1, 2, 3, 456, 789),
      List<int>.generate(16, (index) => index + 1),
    );
    expect(first, '20260821t010203456789z-000102030405060708090a0b0c0d0e0f');
    expect(second, isNot(first));
    expect(first, matches(RegExp(r'^[a-z0-9-]+$')));
  });

  test('run ids reject missing or invalid entropy', () {
    expect(
      () => _buildRunId(DateTime.utc(2026), <int>[1]),
      throwsArgumentError,
    );
    expect(
      () => _buildRunId(DateTime.utc(2026), List<int>.filled(16, 256)),
      throwsArgumentError,
    );
  });

  test('cleanup plan uses exact recorded ids in dependency order', () {
    final ledger = _FixtureLedger('run-1')
      ..record(_FixtureTable.cardCatalog, 'card-1')
      ..record(_FixtureTable.benefits, 'benefit-1')
      ..record(_FixtureTable.cardBenefitMapping, 'mapping-1')
      ..record(_FixtureTable.cardBenefitsStaging, 'staging-1')
      ..record(_FixtureTable.cardCatalogUrlKeys, 'url-hash-1')
      ..record(_FixtureTable.cardCatalogEnrichmentJobs, 'job-1');

    expect(
      ledger.cleanupTargets
          .map((target) => '${target.table.name}:${target.ids.single}')
          .toList(),
      <String>[
        'cardBenefitMapping:mapping-1',
        'cardCatalogEnrichmentJobs:job-1',
        'cardBenefitsStaging:staging-1',
        'cardCatalogUrlKeys:url-hash-1',
        'benefits:benefit-1',
        'cardCatalog:card-1',
      ],
    );
    expect(
      ledger.cleanupTargets.every(
        (target) =>
            target.ids.isNotEmpty && target.ids.every((id) => id.isNotEmpty),
      ),
      isTrue,
    );
  });

  test('marker recovery stays disabled until collision preflight succeeds', () {
    final ledger = _FixtureLedger('run-1');
    expect(ledger.markerRecoveryAllowed, isFalse);
    ledger.allowMarkerRecoveryAfterClearPreflight();
    expect(ledger.markerRecoveryAllowed, isTrue);
  });

  test('benefit preflight rejects either occupied exact dedupe key', () async {
    final fixture = _RunFixture(
      '20260821t010203456789z-000102030405060708090a0b0c0d0e0f',
    );
    for (final occupiedKey in <String>[
      fixture.benefitDedupeKey,
      fixture.proposalDedupeKey,
    ]) {
      final queriedKeys = <String>[];
      await expectLater(
        _assertNoBenefitDedupeCollision(
          fixture,
          loadByDedupeKey: (dedupeKey) async {
            queriedKeys.add(dedupeKey);
            return dedupeKey == occupiedKey
                ? <Map<String, dynamic>>[
                    <String, dynamic>{'benefit_id': 'occupied-id'},
                  ]
                : const <Map<String, dynamic>>[];
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'collision marker',
            contains(occupiedKey),
          ),
        ),
      );
      expect(queriedKeys, <String>[
        fixture.benefitDedupeKey,
        fixture.proposalDedupeKey,
      ]);
    }
  });

  test(
    'benefit recovery records exact ids returned for both run keys',
    () async {
      final fixture = _RunFixture(
        '20260821t010203456789z-000102030405060708090a0b0c0d0e0f',
      );
      final ledger = _FixtureLedger(fixture.runId)
        ..allowMarkerRecoveryAfterClearPreflight();
      final queriedKeys = <String>[];

      await _recoverExactBenefitIds(
        fixture,
        ledger,
        loadByDedupeKey: (dedupeKey) async {
          queriedKeys.add(dedupeKey);
          return <Map<String, dynamic>>[
            <String, dynamic>{
              'benefit_id': dedupeKey == fixture.benefitDedupeKey
                  ? 'active-benefit-id'
                  : 'published-proposal-id',
            },
          ];
        },
      );

      expect(queriedKeys, <String>[
        fixture.benefitDedupeKey,
        fixture.proposalDedupeKey,
      ]);
      expect(ledger.idsFor(_FixtureTable.benefits), <String>{
        'active-benefit-id',
        'published-proposal-id',
      });
    },
  );

  test(
    'benefit residue check catches a published proposal regression',
    () async {
      final fixture = _RunFixture(
        '20260821t010203456789z-000102030405060708090a0b0c0d0e0f',
      );
      final queriedKeys = <String>[];

      await expectLater(
        _assertNoBenefitDedupeResiduals(
          fixture,
          loadByDedupeKey: (dedupeKey) async {
            queriedKeys.add(dedupeKey);
            return dedupeKey == fixture.proposalDedupeKey
                ? <Map<String, dynamic>>[
                    <String, dynamic>{'benefit_id': 'orphaned-proposal-id'},
                  ]
                : const <Map<String, dynamic>>[];
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'residual marker',
            contains(fixture.proposalDedupeKey),
          ),
        ),
      );
      expect(queriedKeys, <String>[
        fixture.benefitDedupeKey,
        fixture.proposalDedupeKey,
      ]);
    },
  );

  test('randomized auth identity remains valid and run scoped', () {
    final fixture = _RunFixture(
      '20260821t010203456789z-000102030405060708090a0b0c0d0e0f',
    );
    final localPart = fixture.reviewerEmail
        .split('@')
        .singleWhere((part) => part != 'example.com');
    expect(localPart.length, lessThanOrEqualTo(64));
    expect(
      fixture.reviewerEmail,
      contains(_sha256(fixture.runId).substring(0, 16)),
    );
    expect(fixture.claimParserVersion, startsWith('task11-harness-'));
    expect(
      fixture.claimParserVersion,
      isNot(anyOf('benefits-v5', 'benefits-v6', 'catalog-v1')),
    );
    expect(_claimParameters(fixture), <String, dynamic>{
      '_max_jobs': 1,
      '_lease_seconds': 60,
      '_run_mode': 'manual',
      '_parser_version': fixture.claimParserVersion,
    });
  });

  test('auth recovery pages to one exact randomized email only', () async {
    final calls = <int>[];
    final matches = await _findExactAuthUserIds(
      expectedEmail: 'ci-run@example.com',
      perPage: 1,
      maxPages: 3,
      loadPage: (page, perPage) async {
        calls.add(page);
        return switch (page) {
          1 => <_AuthIdentity>[
            const _AuthIdentity('other-id', 'other@example.com'),
          ],
          2 => <_AuthIdentity>[
            const _AuthIdentity('run-id', 'CI-RUN@example.com'),
          ],
          _ => const <_AuthIdentity>[],
        };
      },
    );
    expect(matches, <String>{'run-id'});
    expect(calls, <int>[1, 2, 3]);
  });

  test(
    'cleanup coordinator attempts every exact step after failures',
    () async {
      final attempted = <String>[];
      await expectLater(
        _runCleanupSteps(<_CleanupStep>[
          _CleanupStep('recover', () async {
            attempted.add('recover');
            throw StateError('recover failed');
          }),
          _CleanupStep('delete-job', () async {
            attempted.add('delete-job');
          }),
          _CleanupStep('dispose', () async {
            attempted.add('dispose');
            throw StateError('dispose failed');
          }),
        ]),
        throwsA(
          isA<_CleanupException>()
              .having((error) => error.failures.length, 'failure count', 2)
              .having(
                (error) => error.toString(),
                'failure labels',
                allOf(contains('recover'), contains('dispose')),
              ),
        ),
      );
      expect(attempted, <String>['recover', 'delete-job', 'dispose']);
    },
  );

  test('fixture hashing uses the SHA-256 contract expected by the RPCs', () {
    expect(
      _sha256('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  group(
    'guarded hosted benefit-enrichment DB concurrency integration',
    () {
      test(
        'validates exact RLS/RPC staging and removes only run-owned rows',
        () async {
          expect(_hostedConfigurationErrorList, isEmpty);
          final fixture = _RunFixture(_newRunId());
          printOnFailure('Hosted card-ingestion run_id=${fixture.runId}');
          final ledger = _FixtureLedger(fixture.runId);
          final service = SupabaseClient(_supabaseUrl, _serviceRoleKey);
          final unauthenticated = SupabaseClient(_supabaseUrl, _anonKey);
          final authenticated = SupabaseClient(_supabaseUrl, _anonKey);

          try {
            await _assertNoMarkerCollision(service, fixture);
            final existingAuthUsers = await _hostedAuthUserIdsForEmail(
              service,
              fixture.reviewerEmail,
            );
            if (existingAuthUsers.isNotEmpty) {
              throw StateError('run auth marker collision');
            }
            ledger.allowMarkerRecoveryAfterClearPreflight();

            final createdReviewer = await service.auth.admin.createUser(
              AdminUserAttributes(
                email: fixture.reviewerEmail,
                password: fixture.reviewerCredential,
                emailConfirm: true,
              ),
            );
            final reviewerId = createdReviewer.user!.id;
            ledger.authUserIds.add(reviewerId);
            final reviewerProfile = _row(
              await service
                  .from('users')
                  .upsert(<String, dynamic>{
                    'id': reviewerId,
                    'email': fixture.reviewerEmail,
                    'is_admin': true,
                  }, onConflict: 'id')
                  .select('id,is_admin')
                  .single(),
            );
            expect(reviewerProfile['is_admin'], isTrue);
            ledger.record(_FixtureTable.users, reviewerId);
            await authenticated.auth.signInWithPassword(
              email: fixture.reviewerEmail,
              password: fixture.reviewerCredential,
            );

            final card = _row(
              await service
                  .from('card_catalog')
                  .insert(<String, dynamic>{
                    'bank': fixture.issuer,
                    'card_name': fixture.cardName,
                    'network': 'Visa',
                    'card_type': 'credit',
                    'card_url': fixture.sourceUrl,
                    'is_discontinued': false,
                  })
                  .select(
                    'id,card_name,network,annual_fee,joining_fee,apr,'
                    'card_url,is_discontinued,updated_at',
                  )
                  .single(),
            );
            final cardId = card['id'].toString();
            ledger.record(_FixtureTable.cardCatalog, cardId);

            final benefit = _row(
              await service
                  .from('benefits')
                  .insert(<String, dynamic>{
                    'title': 'Hosted harness active benefit',
                    'description': 'Run-scoped active-view fixture.',
                    'benefit_category': 'DINING',
                    'benefit_type': 'percent_discount',
                    'value_config': <String, dynamic>{'rate': 10},
                    'partners': <dynamic>[],
                    'exclusions': <String, dynamic>{
                      'days': <dynamic>[],
                      'mcc_codes': <dynamic>[],
                      'merchants': <dynamic>[],
                      'categories': <dynamic>[],
                      'transaction_types': <dynamic>[],
                      'additional': <String, dynamic>{
                        'source_terms': <dynamic>[],
                      },
                    },
                    'regions': <dynamic>['IN'],
                    'source_url': fixture.sourceUrl,
                    'dedupe_key': fixture.benefitDedupeKey,
                    'is_active': true,
                  })
                  .select('benefit_id')
                  .single(),
            );
            final benefitId = benefit['benefit_id'].toString();
            ledger.record(_FixtureTable.benefits, benefitId);

            final mapping = _row(
              await service
                  .from('card_benefit_mapping')
                  .insert(<String, dynamic>{
                    'card_id': cardId,
                    'benefit_id': benefitId,
                    'display_priority': 1,
                    'is_primary': true,
                    'category_codes': <dynamic>['DINING'],
                  })
                  .select('mapping_id')
                  .single(),
            );
            final mappingId = mapping['mapping_id'].toString();
            ledger.record(_FixtureTable.cardBenefitMapping, mappingId);

            for (final client in <SupabaseClient>[
              unauthenticated,
              authenticated,
            ]) {
              await _expectPermissionDenied(
                () => client.from('card_catalog_enrichment_jobs').select('id'),
                reason: 'non-service clients must not read enrichment jobs',
              );
              await _expectPermissionDenied(
                () => client.rpc(
                  'claim_card_catalog_enrichment_jobs',
                  params: _claimParameters(fixture),
                ),
                reason: 'non-service clients must not claim enrichment jobs',
              );
            }
            expect(
              await authenticated
                  .from('active_card_benefits')
                  .select('mapping_id')
                  .eq('mapping_id', mappingId),
              hasLength(1),
            );

            final job = _row(
              await service
                  .from('card_catalog_enrichment_jobs')
                  .insert(<String, dynamic>{
                    'card_id': cardId,
                    'issuer': fixture.issuer,
                    'canonical_url': fixture.sourceUrl,
                    'final_url_hash': fixture.sourceUrlHash,
                    'parser_version': fixture.claimParserVersion,
                    'status': 'queued',
                    'run_mode': 'manual',
                    'result_summary': <String, dynamic>{
                      'run_id': fixture.runId,
                    },
                  })
                  .select('id')
                  .single(),
            );
            final jobId = job['id'].toString();
            ledger.record(_FixtureTable.cardCatalogEnrichmentJobs, jobId);

            final claimed = _rows(
              await service.rpc(
                'claim_card_catalog_enrichment_jobs',
                params: _claimParameters(fixture),
              ),
            );
            expect(claimed, hasLength(1));
            expect(claimed.single['id'], jobId);
            final leaseToken = claimed.single['lease_token'].toString();
            final isolatedJob = _row(
              await service
                  .from('card_catalog_enrichment_jobs')
                  .update(<String, dynamic>{'parser_version': 'benefits-v5'})
                  .eq('id', jobId)
                  .eq('status', 'processing')
                  .eq('lease_token', leaseToken)
                  .select('id,parser_version')
                  .single(),
            );
            expect(isolatedJob['id'], jobId);
            expect(isolatedJob['parser_version'], 'benefits-v5');

            final proposal = _proposal(fixture);
            final extractedData = <String, dynamic>{
              'request_type': 'official_benefit_enrichment',
              'parser_version': 'benefits-v5',
              'content_hash': fixture.contentHash,
              'proposals': <dynamic>[proposal],
              'diff': <String, dynamic>{
                'additions': <dynamic>[proposal],
                'modifications': <dynamic>[],
                'unchanged': <dynamic>[],
                'possibleRemovals': <dynamic>[],
                'conflicts': <dynamic>[],
              },
            };
            final staged = _rows(
              await service.rpc(
                'stage_card_benefit_enrichment',
                params: <String, dynamic>{
                  '_job_id': jobId,
                  '_lease_token': leaseToken,
                  '_source_url': fixture.sourceUrl,
                  '_source_url_hash': fixture.sourceUrlHash,
                  '_parser_version': 'benefits-v5',
                  '_content_hash': fixture.contentHash,
                  '_extracted_data': extractedData,
                  '_calculated_confidence': 0.99,
                  '_validation_reasons': <dynamic>[
                    <String, dynamic>{'code': 'hosted_db_fixture'},
                  ],
                  '_validation_warnings': <dynamic>[],
                  '_source_evidence': <dynamic>[
                    <String, dynamic>{
                      'evidence_type': 'hosted_db_fixture',
                      'run_id': fixture.runId,
                    },
                  ],
                  '_validated_at': DateTime.now().toUtc().toIso8601String(),
                },
              ),
            );
            expect(staged, hasLength(1));
            expect(staged.single['reused'], isFalse);
            final stagingId = staged.single['staging_id'].toString();
            ledger.record(_FixtureTable.cardBenefitsStaging, stagingId);

            final finalizationParams = <String, dynamic>{
              '_job_id': jobId,
              '_lease_token': leaseToken,
              '_status': 'staged',
              '_staging_id': stagingId,
              '_content_hash': fixture.contentHash,
              '_normalized_fields': <String, dynamic>{'proposed_count': 1},
              '_result_summary': <String, dynamic>{
                'run_id': fixture.runId,
                'proposal_disposition': 'material',
              },
              '_failure_category': null,
              '_next_retry_at': null,
            };
            final finalizations =
                await _runBehindRolledBackAdvisoryLock<
                  List<_AsyncOutcome<dynamic>>
                >(
                  lockIdentity: 'card_benefit_enrichment_review:$cardId',
                  operation: () => Future.wait(<Future<_AsyncOutcome<dynamic>>>[
                    _captureOutcome(
                      service.rpc(
                        'finalize_card_catalog_enrichment_job',
                        params: finalizationParams,
                      ),
                    ),
                    _captureOutcome(
                      service.rpc(
                        'finalize_card_catalog_enrichment_job',
                        params: finalizationParams,
                      ),
                    ),
                  ]),
                );
            expect(finalizations.where((item) => item.succeeded), hasLength(1));
            expect(
              finalizations.singleWhere((item) => item.succeeded).value,
              jobId,
            );
            expect(
              finalizations.singleWhere((item) => !item.succeeded).error,
              isA<PostgrestException>().having(
                (error) => error.message,
                'lease error',
                contains('stale_enrichment_lease'),
              ),
            );

            final rejectionParams = <String, dynamic>{
              '_staging_id': stagingId,
              '_reviewed_by': reviewerId,
              '_decisions': <dynamic>[
                <String, dynamic>{
                  'action': 'reject',
                  'reason': 'hosted harness ${fixture.runId}',
                },
              ],
            };
            final rejections =
                await _runBehindRolledBackAdvisoryLock<
                  List<_AsyncOutcome<dynamic>>
                >(
                  lockIdentity: 'card_benefit_enrichment_review:$cardId',
                  operation: () => Future.wait(<Future<_AsyncOutcome<dynamic>>>[
                    _captureOutcome(
                      service.rpc(
                        'approve_card_benefit_enrichment',
                        params: rejectionParams,
                      ),
                    ),
                    _captureOutcome(
                      service.rpc(
                        'approve_card_benefit_enrichment',
                        params: rejectionParams,
                      ),
                    ),
                  ]),
                );
            expect(rejections.every((item) => item.succeeded), isTrue);
            for (final rejection in rejections) {
              expect(
                _rows(rejection.value).single['resulting_status'],
                'rejected',
              );
            }
            final reviewedStaging = _row(
              await service
                  .from('card_benefits_staging')
                  .select('status,benefit_decisions')
                  .eq('id', stagingId)
                  .single(),
            );
            expect(reviewedStaging['status'], 'rejected');
            expect(reviewedStaging['benefit_decisions'], hasLength(1));

            final cardUpdatedAt = card['updated_at'].toString();
            final pageMoveProposal = _pageMoveProposal(
              fixture: fixture,
              cardId: cardId,
              updatedAt: cardUpdatedAt,
            );
            final pageMoveEvidence = <String, dynamic>{
              'run_id': fixture.runId,
              'content_hash': fixture.contentHash,
              'submitted_url_hash': fixture.movedSourceUrlHash,
              'final_url_hash': fixture.movedSourceUrlHash,
              'source_status': 200,
              'source_type': 'official_html',
              'retrieved_at': cardUpdatedAt,
              'semantic_product_hash': fixture.identitySemanticHash,
            };
            final stagedIdentity = _rows(
              await service.rpc(
                'stage_card_catalog_identity_review',
                params: <String, dynamic>{
                  '_discovery_job_id': null,
                  '_discovery_source': 'issuer_crawl',
                  '_user_id': null,
                  '_issuer': fixture.issuer,
                  '_proposed_product': fixture.cardName,
                  '_dedupe_key': fixture.identityDedupeKey,
                  '_semantic_hash': fixture.identitySemanticHash,
                  '_proposed_fields': pageMoveProposal,
                  '_source_evidence': pageMoveEvidence,
                  '_existing_candidates': <dynamic>[
                    <String, dynamic>{'card_id': cardId},
                  ],
                  '_validation_warnings': <dynamic>[],
                  '_confidence': 0.99,
                  '_expected_job_status': null,
                  '_expected_job_updated_at': null,
                },
              ),
            ).single;
            expect(stagedIdentity['resulting_status'], 'review_required');
            final discoveryJobId = stagedIdentity['job_id'].toString();
            final reviewItemId = stagedIdentity['review_item_id'].toString();
            ledger.record(_FixtureTable.cardDiscoveryJobs, discoveryJobId);
            ledger.record(_FixtureTable.cardCatalogReviewQueue, reviewItemId);

            final publicationParams = <String, dynamic>{
              '_discovery_job_id': discoveryJobId,
              '_review_item_id': reviewItemId,
              '_actor_id': reviewerId,
              '_action': 'edit_approve',
              '_reviewed_fields': <String, dynamic>{},
              '_merge_card_id': null,
              '_reason': null,
              '_parser_version': 'benefits-v6',
            };
            await _runCatalogPublicationRollbackProbe(
              discoveryJobId: discoveryJobId,
              reviewItemId: reviewItemId,
              actorId: reviewerId,
            );
            final publications =
                await _runBehindRolledBackAdvisoryLock<
                  List<_AsyncOutcome<dynamic>>
                >(
                  lockIdentity: 'card_catalog_publication:job:$discoveryJobId',
                  operation: () => Future.wait(<Future<_AsyncOutcome<dynamic>>>[
                    _captureOutcome(
                      service.rpc(
                        'publish_card_catalog_identity',
                        params: publicationParams,
                      ),
                    ),
                    _captureOutcome(
                      service.rpc(
                        'publish_card_catalog_identity',
                        params: publicationParams,
                      ),
                    ),
                  ]),
                );
            expect(
              publications.every((item) => item.succeeded),
              isTrue,
              reason: publications
                  .map((item) => item.error?.toString() ?? 'success')
                  .join(' | '),
            );
            for (final publication in publications) {
              final published = _rows(publication.value).single;
              expect(published['card_id'], cardId);
              expect(published['resulting_status'], 'approved');
            }
            expect(
              _row(
                await service
                    .from('card_catalog')
                    .select('card_url')
                    .eq('id', cardId)
                    .single(),
              )['card_url'],
              fixture.movedSourceUrl,
            );
            final publishedUrlKeys = _rows(
              await service
                  .from('card_catalog_url_keys')
                  .select('url_hash,card_id')
                  .inFilter('url_hash', <String>[
                    fixture.sourceUrlHash,
                    fixture.movedSourceUrlHash,
                  ]),
            );
            expect(publishedUrlKeys, hasLength(2));
            expect(
              publishedUrlKeys.every((row) => row['card_id'] == cardId),
              isTrue,
            );
            for (final row in publishedUrlKeys) {
              ledger.record(
                _FixtureTable.cardCatalogUrlKeys,
                row['url_hash'].toString(),
              );
            }
            final provenanceRows = _rows(
              await service
                  .from('card_catalog_provenance')
                  .select('id')
                  .eq('card_id', cardId),
            );
            expect(provenanceRows, hasLength(2));
            for (final row in provenanceRows) {
              ledger.record(
                _FixtureTable.cardCatalogProvenance,
                row['id'].toString(),
              );
            }
            final publicationAudits = _rows(
              await service
                  .from('card_catalog_review_audit')
                  .select('id,action')
                  .eq('review_item_id', reviewItemId),
            );
            expect(publicationAudits, hasLength(1));
            expect(publicationAudits.single['action'], 'edit_approve');
            ledger.record(
              _FixtureTable.cardCatalogReviewAudit,
              publicationAudits.single['id'].toString(),
            );
            final v6Jobs = _rows(
              await service
                  .from('card_catalog_enrichment_jobs')
                  .select('id')
                  .eq('card_id', cardId)
                  .eq('parser_version', 'benefits-v6'),
            );
            expect(v6Jobs, hasLength(1));
            ledger.record(
              _FixtureTable.cardCatalogEnrichmentJobs,
              v6Jobs.single['id'].toString(),
            );

            final anchor = _row(
              await service
                  .from('card_discovery_jobs')
                  .insert(<String, dynamic>{
                    'user_id': null,
                    'issuer': fixture.issuer,
                    'proposed_product': null,
                    'evidence': <String, dynamic>{
                      'kind': 'issuer_directory_run',
                      'issuer': fixture.issuer,
                      'canonical_url': fixture.sourceUrl,
                      'run_date': DateTime.now()
                          .toUtc()
                          .toIso8601String()
                          .substring(0, 10),
                    },
                    'dedupe_key': fixture.quarantineAnchorDedupeKey,
                    'status': 'failed',
                    'attempt_count': 5,
                    'next_retry_at': null,
                    'failure_category': 'issuer_discovery_quarantined',
                    'discovery_source': 'issuer_crawl',
                  })
                  .select('id,evidence')
                  .single(),
            );
            final anchorJobId = anchor['id'].toString();
            ledger.record(_FixtureTable.cardDiscoveryJobs, anchorJobId);

            Future<List<String>> createQuarantineReview(int episode) async {
              final observation = _quarantineSourceObservation(
                anchorJobId: anchorJobId,
                issuer: fixture.issuer,
                episode: episode,
              );
              final fence = <String, dynamic>{
                'version': 1,
                'classification': 'issuer_discovery_quarantine',
                'anchor_job_id': anchorJobId,
                'reason': 'resume_attempts_exhausted',
                'retryable': true,
                'retryability_reason': 'attempt_budget_reset_allowed',
                'issuer': fixture.issuer,
                'episode': episode,
                'semantic_identity': observation['episode_identity'],
              };
              await service
                  .from('card_discovery_jobs')
                  .update(<String, dynamic>{
                    'status': 'failed',
                    'attempt_count': 5,
                    'next_retry_at': null,
                    'failure_category': 'issuer_discovery_quarantined',
                    'evidence': <String, dynamic>{
                      'kind': 'issuer_directory_run',
                      'issuer': fixture.issuer,
                      'canonical_url': fixture.sourceUrl,
                      'run_date': DateTime.now()
                          .toUtc()
                          .toIso8601String()
                          .substring(0, 10),
                      'quarantine_fence': fence,
                    },
                  })
                  .eq('id', anchorJobId);
              final reviewJob = _row(
                await service
                    .from('card_discovery_jobs')
                    .insert(<String, dynamic>{
                      'user_id': null,
                      'issuer': fixture.issuer,
                      'proposed_product': 'Issuer discovery quarantine',
                      'evidence': <String, dynamic>{
                        'kind': 'issuer_discovery_quarantine_review',
                        'run_id': fixture.runId,
                        'episode': episode,
                      },
                      'dedupe_key': fixture.quarantineReviewDedupeKeyFor(
                        episode,
                      ),
                      'status': 'review_required',
                      'attempt_count': 0,
                      'discovery_source': 'issuer_crawl',
                    })
                    .select('id')
                    .single(),
              );
              final reviewJobId = reviewJob['id'].toString();
              ledger.record(_FixtureTable.cardDiscoveryJobs, reviewJobId);
              final review = _row(
                await service
                    .from('card_catalog_review_queue')
                    .insert(<String, dynamic>{
                      'discovery_job_id': reviewJobId,
                      'proposed_fields': <String, dynamic>{
                        'source_observation': observation,
                      },
                      'source_evidence': <String, dynamic>{
                        'source_observation': observation,
                      },
                      'existing_candidates': <dynamic>[],
                      'validation_warnings': <dynamic>[],
                      'confidence': 1,
                      'status': 'pending',
                    })
                    .select('id')
                    .single(),
              );
              final quarantineReviewId = review['id'].toString();
              ledger.record(
                _FixtureTable.cardCatalogReviewQueue,
                quarantineReviewId,
              );
              await service
                  .from('card_discovery_jobs')
                  .update(<String, dynamic>{
                    'review_item_id': quarantineReviewId,
                  })
                  .eq('id', reviewJobId);
              return <String>[reviewJobId, quarantineReviewId];
            }

            for (final episode in <int>[1, 2]) {
              final quarantineIds = await createQuarantineReview(episode);
              final reviewJobId = quarantineIds[0];
              final quarantineReviewId = quarantineIds[1];
              final retryParams = <String, dynamic>{
                '_discovery_job_id': reviewJobId,
                '_review_item_id': quarantineReviewId,
                '_actor_id': reviewerId,
                '_action': 'retry',
                '_reviewed_fields': <String, dynamic>{},
                '_merge_card_id': null,
                '_reason': 'Task11 concurrency retry episode $episode',
                '_parser_version': 'benefits-v6',
              };
              final retries =
                  await _runBehindRolledBackAdvisoryLock<
                    List<_AsyncOutcome<dynamic>>
                  >(
                    lockIdentity: 'card_catalog_publication:job:$reviewJobId',
                    operation: () =>
                        Future.wait(<Future<_AsyncOutcome<dynamic>>>[
                          _captureOutcome(
                            service.rpc(
                              'publish_card_catalog_identity',
                              params: retryParams,
                            ),
                          ),
                          _captureOutcome(
                            service.rpc(
                              'publish_card_catalog_identity',
                              params: retryParams,
                            ),
                          ),
                        ]),
                  );
              expect(
                retries.every((item) => item.succeeded),
                isTrue,
                reason: retries
                    .map((item) => item.error?.toString() ?? 'success')
                    .join(' | '),
              );
              for (final retry in retries) {
                expect(
                  _rows(retry.value).single['resulting_status'],
                  'resolved',
                );
              }
              final retryAudits = _rows(
                await service
                    .from('card_catalog_review_audit')
                    .select('id,action')
                    .eq('review_item_id', quarantineReviewId),
              );
              expect(retryAudits, hasLength(1));
              expect(retryAudits.single['action'], 'retry');
              ledger.record(
                _FixtureTable.cardCatalogReviewAudit,
                retryAudits.single['id'].toString(),
              );
            }
            final retriedAnchor = _row(
              await service
                  .from('card_discovery_jobs')
                  .select(
                    'status,attempt_count,next_retry_at,failure_category,'
                    'evidence',
                  )
                  .eq('id', anchorJobId)
                  .single(),
            );
            expect(retriedAnchor['status'], 'failed');
            expect(retriedAnchor['attempt_count'], 0);
            expect(retriedAnchor['next_retry_at'], isNotNull);
            expect(
              retriedAnchor['failure_category'],
              'issuer_discovery_operator_retry',
            );
            expect(
              Map<String, dynamic>.from(
                Map<String, dynamic>.from(
                      retriedAnchor['evidence'] as Map,
                    )['quarantine_fence']
                    as Map,
              )['episode'],
              2,
            );
            expect(
              await service
                  .from('card_catalog_enrichment_jobs')
                  .select('status')
                  .eq('id', jobId)
                  .single(),
              containsPair('status', 'completed'),
            );
          } finally {
            await _runCleanupSteps(<_CleanupStep>[
              if (ledger.markerRecoveryAllowed)
                _CleanupStep(
                  'recover exact run IDs',
                  () => _recoverExactCreatedIds(service, fixture, ledger),
                ),
              for (final table in _FixtureTable.values)
                _CleanupStep(
                  'delete exact ${table.databaseName} IDs',
                  () => _deleteRecordedTable(service, ledger, table),
                ),
              _CleanupStep('delete exact Auth user IDs', () async {
                for (final userId in ledger.authUserIds) {
                  await service.auth.admin.deleteUser(userId);
                }
              }),
              _CleanupStep(
                'verify zero run residuals',
                () => _verifyZeroResidualRows(service, fixture, ledger),
              ),
              _CleanupStep('dispose Supabase clients', () async {
                service.dispose();
                unauthenticated.dispose();
                authenticated.dispose();
              }),
            ]);
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: _hostedConcurrencySkipReason,
  );
}
