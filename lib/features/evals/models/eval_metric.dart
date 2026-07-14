/// A single scored metric for one AI subsystem, used across all eval panels
/// and for computing the Overall Health Score.
class EvalMetric {
  const EvalMetric({
    required this.name,
    required this.value, // 0.0–1.0 normalised
    required this.displayValue, // human-readable string
    this.trend,
    this.description,
    this.sampleSize,
  });

  final String name;

  /// Normalised score 0.0 (worst) – 1.0 (best).
  final double value;

  /// Human-readable display string, e.g. "87.3 %", "142 ms", "4 / 5".
  final String displayValue;

  /// 'up' | 'down' | 'stable' | null (unknown).
  final String? trend;

  /// Optional tooltip / explanation copy.
  final String? description;

  /// How many data points this metric is based on.
  final int? sampleSize;

  /// Colour bucket based on [value].
  EvalHealthBucket get bucket {
    if (value >= 0.8) return EvalHealthBucket.good;
    if (value >= 0.5) return EvalHealthBucket.warn;
    return EvalHealthBucket.bad;
  }
}

enum EvalHealthBucket { good, warn, bad }

/// Subsystem-level summary returned by [EvalAggregator].
class SubsystemScore {
  const SubsystemScore({
    required this.name,
    required this.icon,
    required this.score, // 0.0–1.0
    required this.metrics,
    this.weight = 1.0,
  });

  final String name;
  final String icon; // emoji icon for the tab label
  final double score;
  final List<EvalMetric> metrics;

  /// Weight used when calculating the overall health score.
  final double weight;

  EvalHealthBucket get bucket {
    if (score >= 0.8) return EvalHealthBucket.good;
    if (score >= 0.5) return EvalHealthBucket.warn;
    return EvalHealthBucket.bad;
  }
}
