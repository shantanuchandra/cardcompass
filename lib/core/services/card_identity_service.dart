import 'dart:convert';

import 'card_normalizer_service.dart';

class CardCatalogIdentity {
  const CardCatalogIdentity({
    required this.id,
    required this.issuer,
    required this.name,
    this.network,
    this.aliases = const [],
  });

  final String id;
  final String issuer;
  final String name;
  final String? network;
  final List<String> aliases;
}

class CardIdentityEvidence {
  const CardIdentityEvidence({
    required this.issuer,
    this.subjectProduct,
    this.filenameProduct,
    this.pdfHeaderProduct,
    this.network,
    this.lastFour,
    this.attachmentFilename,
    this.pdfHeaderExcerpt,
    this.warnings = const [],
  });

  final String issuer;
  final String? subjectProduct;
  final String? filenameProduct;
  final String? pdfHeaderProduct;
  final String? network;
  final String? lastFour;
  final String? attachmentFilename;
  final String? pdfHeaderExcerpt;
  final List<String> warnings;

  List<String> get productSignals => [
    subjectProduct,
    filenameProduct,
    pdfHeaderProduct,
  ].whereType<String>().toSet().toList(growable: false);

  factory CardIdentityEvidence.extract({
    required String issuer,
    String? subject,
    String? attachmentFilename,
    String? pdfHeader,
  }) {
    final boundedHeader = pdfHeader?.substring(
      0,
      pdfHeader.length.clamp(0, 12000),
    );
    final subjectProduct = _productFromSubject(subject ?? '', issuer);
    final filenameProduct = _productFromFilename(
      attachmentFilename ?? '',
      issuer,
    );
    final headerProduct = _productFromHeader(boundedHeader ?? '', issuer);
    final network = _networkFrom(
      '${subject ?? ''}\n${attachmentFilename ?? ''}\n${boundedHeader ?? ''}',
    );
    final lastFour = _lastFourFrom(
      '${attachmentFilename ?? ''}\n${boundedHeader ?? ''}',
    );
    final products = [subjectProduct, filenameProduct, headerProduct]
        .whereType<String>()
        .map(normalizeCardProduct)
        .where((value) => value.isNotEmpty)
        .toSet();

    return CardIdentityEvidence(
      issuer: CardNormalizerService.normalizeBankName(issuer),
      subjectProduct: subjectProduct,
      filenameProduct: filenameProduct,
      pdfHeaderProduct: headerProduct,
      network: network,
      lastFour: lastFour,
      attachmentFilename: attachmentFilename?.trim().isEmpty ?? true
          ? null
          : attachmentFilename,
      pdfHeaderExcerpt: boundedHeader == null
          ? null
          : _safeHeaderExcerpt(boundedHeader),
      warnings: products.length > 1 ? const ['conflicting_product_signals'] : const [],
    );
  }

  Map<String, dynamic> toSafeJson() => {
    'issuer': issuer,
    if (subjectProduct != null) 'subject_product': subjectProduct,
    if (filenameProduct != null) 'filename_product': filenameProduct,
    if (pdfHeaderProduct != null) 'pdf_header_product': pdfHeaderProduct,
    if (network != null) 'network': network,
    if (lastFour != null) 'last_four': lastFour,
    if (attachmentFilename != null)
      'attachment_filename': _safeFilename(attachmentFilename!),
    if (pdfHeaderExcerpt != null) 'pdf_header_excerpt': pdfHeaderExcerpt,
    'product_signals': productSignals,
    'warnings': warnings,
    'confidence': confidence,
  };

  double get confidence {
    if (productSignals.isEmpty) return 0;
    if (warnings.isNotEmpty) return 0.55;
    if (pdfHeaderProduct != null && productSignals.length == 1) return 0.95;
    if (subjectProduct != null || filenameProduct != null) return 0.9;
    return 0.7;
  }
}

class CardIdentityMatcher {
  const CardIdentityMatcher();

  CardCatalogIdentity? match(
    CardIdentityEvidence evidence,
    Iterable<CardCatalogIdentity> candidates,
  ) {
    final issuer = CardNormalizerService.normalizeBankName(evidence.issuer);
    final sameIssuer = candidates
        .where(
          (candidate) =>
              CardNormalizerService.normalizeBankName(candidate.issuer) == issuer,
        )
        .toList(growable: false);
    if (sameIssuer.isEmpty || evidence.productSignals.isEmpty) return null;

    final scored = <({CardCatalogIdentity card, int score, int specificity})>[];
    for (final card in sameIssuer) {
      var best = 0;
      var specificity = 0;
      for (final label in [card.name, ...card.aliases]) {
        final normalizedLabel = normalizeCardProduct(label);
        final labelTokens = productTokens(label);
        for (final signal in evidence.productSignals) {
          final normalizedSignal = normalizeCardProduct(signal);
          final signalTokens = productTokens(signal);
          var score = 0;
          if (normalizedSignal == normalizedLabel) {
            score = label == card.name ? 500 : 450;
          } else if (labelTokens.isNotEmpty && labelTokens.every(signalTokens.contains)) {
            score = 300 + labelTokens.length * 10;
          }
          if (score > best) {
            best = score;
            specificity = labelTokens.length * 100 + normalizedLabel.length;
          }
        }
      }
      if (best > 0) scored.add((card: card, score: best, specificity: specificity));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.specificity.compareTo(a.specificity);
    });
    final winner = scored.first;
    final tied = scored.where(
      (item) => item.score == winner.score && item.specificity == winner.specificity,
    );
    return tied.length == 1 ? winner.card : null;
  }
}

String normalizeCardProduct(String value) => productTokens(value).join('');

List<String> productTokens(String value) {
  var spaced = value
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .replaceAll('american express', 'amex')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  const ignored = {
    'bank', 'credit', 'card', 'statement', 'your', 'for', 'the', 'hdfc',
    'axis', 'icici', 'kotak', 'indusind', 'hsbc', 'sbi', 'first', 'club',
    'amex', 'visa', 'mastercard', 'rupay', 'norm', 'retail', 'cc', 'stmt',
  };
  return spaced
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty && !ignored.contains(token))
      .toList(growable: false);
}

String? _productFromSubject(String subject, String issuer) {
  if (subject.trim().isEmpty) return null;
  var value = subject;
  value = value.replaceAll(RegExp(r'\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-\s,]*20\d{2}\b', caseSensitive: false), ' ');
  value = value.replaceAll(RegExp(r'\b(?:statement\s+email|credit\s+card\s+statement|card\s+statement|statement)\b', caseSensitive: false), ' ');
  value = value.replaceAll(RegExp(r'\b(?:ending|period|is\s+here)\b.*$', caseSensitive: false), ' ');
  value = value.replaceAll(RegExp(r'\b(?:your|for)\b', caseSensitive: false), ' ');
  value = _removeIssuer(value, issuer);
  value = value.replaceAll(RegExp(r'\b(?:amex|visa|mastercard|rupay)\b', caseSensitive: false), ' ');
  value = value.replaceAll(RegExp(r'\b(?:x{1,16}\d{0,4}|\d{1,2})\b', caseSensitive: false), ' ');
  return _cleanProduct(value);
}

String? _productFromFilename(String filename, String issuer) {
  if (filename.trim().isEmpty) return null;
  var decoded = filename;
  try {
    decoded = Uri.decodeComponent(filename);
  } catch (_) {
    decoded = filename;
  }
  decoded = decoded.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  final retail = RegExp(r'(?:^|[_\-])retail[_\-]([a-z0-9]+)', caseSensitive: false).firstMatch(decoded);
  if (retail != null) return _cleanProduct(retail.group(1)!);

  var value = decoded
      .replaceAll(RegExp(r'x{2,}\d{0,4}', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b\d{2,}\b'), ' ')
      .replaceAll(RegExp(r'[_\-]+'), ' ');
  value = _removeIssuer(value, issuer);
  value = value.replaceAll(RegExp(r'\b(?:statement|stmt|credit|card|norm|retail|pdf)\b', caseSensitive: false), ' ');
  return _cleanProduct(value);
}

String? _productFromHeader(String header, String issuer) {
  if (header.trim().isEmpty) return null;
  for (final line in const LineSplitter().convert(header).take(40)) {
    if (!RegExp(r'credit\s*card', caseSensitive: false).hasMatch(line)) continue;
    var value = line.replaceAll(RegExp(r'credit\s*card(?:\s*statement)?', caseSensitive: false), ' ');
    value = _removeIssuer(value, issuer);
    value = value.replaceAll(RegExp(r'\b(?:amex|visa|mastercard|rupay)\b', caseSensitive: false), ' ');
    final product = _cleanProduct(value);
    if (product != null) return product;
  }
  return null;
}

String _removeIssuer(String value, String issuer) {
  var result = value;
  final normalizedIssuer = CardNormalizerService.normalizeBankName(issuer);
  for (final word in normalizedIssuer.split(RegExp(r'\s+'))) {
    if (word.length < 3 || word.toLowerCase() == 'bank') continue;
    result = result.replaceAll(RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false), ' ');
  }
  return result.replaceAll(RegExp(r'\bbank\b', caseSensitive: false), ' ');
}

String? _cleanProduct(String value) {
  final spaced = value
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim();
  final tokens = productTokens(spaced);
  if (tokens.isEmpty || tokens.every((token) => RegExp(r'^\d+$').hasMatch(token))) {
    return null;
  }
  return tokens.map(_displayToken).join(' ');
}

String _displayToken(String value) {
  const display = {'eazydiner': 'EazyDiner', 'sapphiro': 'Sapphiro'};
  return display[value] ?? '${value[0].toUpperCase()}${value.substring(1)}';
}

String? _networkFrom(String value) {
  if (RegExp(r'\b(?:american\s*express|amex)\b', caseSensitive: false).hasMatch(value)) {
    return 'American Express';
  }
  if (RegExp(r'\bmastercard\b', caseSensitive: false).hasMatch(value)) return 'Mastercard';
  if (RegExp(r'\brupay\b', caseSensitive: false).hasMatch(value)) return 'RuPay';
  if (RegExp(r'\bvisa\b', caseSensitive: false).hasMatch(value)) return 'Visa';
  return null;
}

String? _lastFourFrom(String value) {
  final patterns = [
    RegExp(r'(?:primary\s+card\s+number|card\s+ending)[^\n]{0,48}?(\d(?:\s*\d){3})(?!\s*\d)', caseSensitive: false),
    RegExp(r'(?:x{1,12}|\*{1,12})\s*(\d{4})(?!\d)', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(value);
    if (match != null) return match.group(1)!.replaceAll(RegExp(r'\D'), '');
  }
  return null;
}

String _safeFilename(String value) => value.replaceAll(
  RegExp(r'(?<!\d)\d{6,}(?!\d)'),
  '[redacted]',
);

String _safeHeaderExcerpt(String value) {
  final safeLines = <String>[];
  for (final line in const LineSplitter().convert(value)) {
    if (!RegExp(r'(credit\s*card|primary\s+card|card\s+ending|amex|visa|mastercard|rupay)', caseSensitive: false).hasMatch(line)) {
      continue;
    }
    safeLines.add(
      line
          .replaceAll(RegExp(r'(?<!\d)(?:\d[\s-]*){6,}(?!\d)'), '[redacted]')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
    if (safeLines.length == 4) break;
  }
  return safeLines.join('\n');
}
