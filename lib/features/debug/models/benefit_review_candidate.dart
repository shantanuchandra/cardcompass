enum BenefitDecision { unresolved, accepted, rejected }

class BenefitReviewCandidate {
  const BenefitReviewCandidate({
    required this.id,
    required this.kind,
    required this.description,
    required this.source,
    this.decision = BenefitDecision.unresolved,
    this.selected = false,
  });

  final String id;
  final String kind;
  final String description;
  final Map<String, dynamic> source;
  final BenefitDecision decision;
  final bool selected;

  BenefitReviewCandidate copyWith({
    BenefitDecision? decision,
    bool? selected,
  }) {
    return BenefitReviewCandidate(
      id: id,
      kind: kind,
      description: description,
      source: source,
      decision: decision ?? this.decision,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toStagingJson() {
    return {
      'id': id,
      'kind': kind,
      'description': description,
      'source': source,
      'decision': decision.name,
    };
  }
}

class BenefitReviewState {
  const BenefitReviewState(this.items);

  final List<BenefitReviewCandidate> items;

  bool get hasUnresolved =>
      items.any((item) => item.decision == BenefitDecision.unresolved);

  factory BenefitReviewState.fromExtractedData(Map<String, dynamic> data) {
    final items = <BenefitReviewCandidate>[];

    void addItems(String collectionKey, String kindKey, String descriptionKey) {
      final rawItems = data[collectionKey];
      if (rawItems is! List) return;
      for (var index = 0; index < rawItems.length; index++) {
        final raw = rawItems[index];
        if (raw is! Map) continue;
        final source = Map<String, dynamic>.from(raw);
        items.add(BenefitReviewCandidate(
          id: '$collectionKey:$index',
          kind: source[kindKey]?.toString().toUpperCase() ?? 'GENERAL',
          description: source[descriptionKey]?.toString() ?? 'Benefit',
          source: source,
        ));
      }
    }

    addItems('cashback_benefits', 'category', 'description');
    addItems('special_benefits', 'type', 'description');

    final rewardPoints = data['reward_points'];
    if (rewardPoints is Map) {
      final rewards = Map<String, dynamic>.from(rewardPoints);
      final baseRate = rewards['base_rate'];
      if (baseRate != null) {
        items.add(BenefitReviewCandidate(
          id: 'reward_points:base_rate',
          kind: 'REWARDS',
          description: 'Base reward points: $baseRate',
          source: {
            'category': 'GENERAL',
            'description': 'Base reward points',
            'rate': baseRate,
            'rate_type': 'points',
          },
        ));
      }
      final accelerated = rewards['accelerated_categories'];
      if (accelerated is List) {
        for (var index = 0; index < accelerated.length; index++) {
          final raw = accelerated[index];
          if (raw is! Map) continue;
          final source = Map<String, dynamic>.from(raw);
          items.add(BenefitReviewCandidate(
            id: 'reward_points:accelerated:$index',
            kind: source['category']?.toString().toUpperCase() ?? 'REWARDS',
            description: source['description']?.toString() ??
                'Accelerated reward points',
            source: source,
          ));
        }
      }
    }

    return BenefitReviewState(List.unmodifiable(items));
  }

  BenefitReviewState setDecision(int index, BenefitDecision decision) {
    return _replace(index, items[index].copyWith(decision: decision));
  }

  BenefitReviewState setSelected(int index, bool selected) {
    return _replace(index, items[index].copyWith(selected: selected));
  }

  BenefitReviewState acceptSelected() =>
      _applyToSelected(BenefitDecision.accepted);

  BenefitReviewState rejectSelected() =>
      _applyToSelected(BenefitDecision.rejected);

  /// Discarding a whole candidate set is an explicit rejection for every item.
  BenefitReviewState rejectAll() => BenefitReviewState(List.unmodifiable(
        items
            .map((item) => item.decision == BenefitDecision.unresolved
                ? item.copyWith(decision: BenefitDecision.rejected)
                : item)
            .toList(),
      ));

  BenefitReviewState _applyToSelected(BenefitDecision decision) {
    return BenefitReviewState(List.unmodifiable(items.map((item) {
      if (!item.selected || item.decision != BenefitDecision.unresolved) {
        return item;
      }
      return item.copyWith(decision: decision, selected: false);
    }).toList()));
  }

  BenefitReviewState _replace(int index, BenefitReviewCandidate item) {
    final next = List<BenefitReviewCandidate>.from(items);
    next[index] = item;
    return BenefitReviewState(List.unmodifiable(next));
  }

  Map<String, dynamic> toStagingJson() {
    return {'items': items.map((item) => item.toStagingJson()).toList()};
  }
}
