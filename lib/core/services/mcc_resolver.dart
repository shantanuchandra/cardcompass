enum MccSource {
  bankStatement,
  verifiedProvider,
  merchantRegistry,
  inferred,
  unknown,
}

extension MccSourceDatabaseValue on MccSource {
  String get databaseValue => switch (this) {
    MccSource.bankStatement => 'bank_statement',
    MccSource.verifiedProvider => 'verified_provider',
    MccSource.merchantRegistry => 'merchant_registry',
    MccSource.inferred => 'inferred',
    MccSource.unknown => 'unknown',
  };
}

class MccCandidate {
  const MccCandidate({
    required this.code,
    required this.source,
    required this.confidence,
    this.description,
    this.verifiedAt,
  });

  final String code;
  final String? description;
  final MccSource source;
  final double confidence;
  final DateTime? verifiedAt;
}

MccCandidate? resolveMcc({
  MccCandidate? bankStatement,
  MccCandidate? verifiedProvider,
  MccCandidate? merchantRegistry,
  MccCandidate? inferred,
}) {
  return bankStatement ?? verifiedProvider ?? merchantRegistry ?? inferred;
}
