import 'package:cardcompass/core/services/mcc_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('issuer MCC outranks inferred MCC', () {
    final result = resolveMcc(
      bankStatement: const MccCandidate(
        code: '5541',
        source: MccSource.bankStatement,
        confidence: 1,
      ),
      inferred: const MccCandidate(
        code: '5812',
        source: MccSource.inferred,
        confidence: .65,
      ),
    );

    expect(result!.code, '5541');
    expect(result.source, MccSource.bankStatement);
  });

  test('verified provider and registry precede inference', () {
    final result = resolveMcc(
      verifiedProvider: const MccCandidate(
        code: '5411',
        source: MccSource.verifiedProvider,
        confidence: .98,
      ),
      merchantRegistry: const MccCandidate(
        code: '5499',
        source: MccSource.merchantRegistry,
        confidence: .9,
      ),
      inferred: const MccCandidate(
        code: '5812',
        source: MccSource.inferred,
        confidence: .65,
      ),
    );

    expect(result!.code, '5411');
    expect(result.source, MccSource.verifiedProvider);
  });

  test('inferred result remains labelled and below full confidence', () {
    final result = resolveMcc(
      inferred: const MccCandidate(
        code: '5812',
        source: MccSource.inferred,
        confidence: .65,
      ),
    );

    expect(result!.source, MccSource.inferred);
    expect(result.confidence, lessThan(1));
  });
}
