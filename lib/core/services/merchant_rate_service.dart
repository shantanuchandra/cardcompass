// cardcompass/lib/core/services/merchant_rate_service.dart

class MerchantRateService {
  final Map<String, double> _merchantRates = {
    'swiggy': 1.5,  // 50% bonus for Swiggy
    'zomato': 1.3,  // 30% bonus for Zomato
    'amazon': 1.2,  // 20% bonus for Amazon
    'flipkart': 1.1, // 10% bonus for Flipkart
  };

  final Map<String, double> _categoryRates = {
    'dining': 1.4,    // 40% bonus for dining
    'travel': 1.3,    // 30% bonus for travel
    'groceries': 1.2, // 20% bonus for groceries
    'fuel': 1.1,      // 10% bonus for fuel
  };

  // Method to fetch combined merchant and category reward multiplier
  double getCombinedRate(String merchantName, String category) {
    final merchantRate = getMerchantRate(merchantName);
    final categoryRate = getCategoryRate(category);
    
    // Multiply the rates for combined effect
    return merchantRate * categoryRate;
  }

  // Method to fetch merchant-specific reward rates
  double getMerchantRate(String merchantName) {
    // Normalize merchant name for lookup
    final normalizedMerchant = merchantName.toLowerCase().trim();
    
    // Check for exact matches first
    if (_merchantRates.containsKey(normalizedMerchant)) {
      return _merchantRates[normalizedMerchant]!;
    }

    // Check for partial matches in merchant name
    for (final merchant in _merchantRates.keys) {
      if (normalizedMerchant.contains(merchant)) {
        return _merchantRates[merchant]!;
      }
    }

    // Default rate if no special merchant rate found
    return 1.0;
  }

  // Method to fetch category-specific reward rates
  double getCategoryRate(String category) {
    // Normalize category name for lookup
    final normalizedCategory = category.toLowerCase().trim();
    
    return _categoryRates[normalizedCategory] ?? 1.0;
  }

  // Method to get all merchant rates for debugging
  Map<String, double> getAllMerchantRates() {
    return Map.from(_merchantRates);
  }

  // Method to get all category rates for debugging
  Map<String, double> getAllCategoryRates() {
    return Map.from(_categoryRates);
  }
}
