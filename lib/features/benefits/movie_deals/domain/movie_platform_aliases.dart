// lib/features/benefits/movie_deals/domain/movie_platform_aliases.dart
import 'movie_deal_rule.dart';

/// Canonical movie-booking-platform vocabulary and alias map (design spec
/// §8). A CHECKED-IN CONSTANT, not derived at runtime from benefit data —
/// this is what makes a multi-partner milestone/rewardMultiplier row's
/// eligibleMoviePlatforms deterministic rather than left to inference.
/// Grow this map as new real movie-booking partners appear in future data.
const Map<String, String> moviePlatformAliases = {
  'bookmyshow': 'BookMyShow',
  'district': 'Zomato',
  'zomato': 'Zomato',
  'pvr': 'PVR',
  'inox': 'INOX',
  'cinepolis': 'Cinepolis',
  'moviemax': 'Moviemax',
};

String _normalize(String value) => value.trim().toLowerCase();

/// The movie-specific, registry-filtered projection of [rule.partners] —
/// THIS is what platform confidence (§5) and eligibility (§7) actually
/// check, never raw `rule.partners` directly. For a single-purpose offer
/// (percentDiscount/fixedDiscount/bogo) this equals partners verbatim
/// (mapped through the alias table). For a multi-partner milestone/
/// rewardMultiplier row, this is the intersection with the registry —
/// non-movie partners (Uber, cult.fit Live, Big Basket, OYO, Swiggy) are
/// never included, regardless of how many partners the raw benefit lists.
Set<String> eligibleMoviePlatformsFor(MovieDealRule rule) {
  final result = <String>{};
  for (final partner in rule.partners) {
    final canonical = moviePlatformAliases[_normalize(partner)];
    if (canonical != null) result.add(canonical);
  }
  return result;
}
