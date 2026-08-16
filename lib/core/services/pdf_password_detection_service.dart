import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'password_learning_service.dart';
import 'parsing_logger.dart';

enum ManualPasswordOutcome { succeeded, cancelled, attemptsExhausted }

class ManualPasswordAttemptResult {
  const ManualPasswordAttemptResult({required this.outcome, this.text});

  final ManualPasswordOutcome outcome;
  final String? text;
}

Future<ManualPasswordAttemptResult> runManualPasswordAttempts({
  required Future<String?> Function(int attempt, int maxAttempts)
  requestPassword,
  required Future<String?> Function(String password) verifyPassword,
  int maxAttempts = 2,
}) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final password = await requestPassword(attempt, maxAttempts);
    if (password == null || password.isEmpty) {
      return const ManualPasswordAttemptResult(
        outcome: ManualPasswordOutcome.cancelled,
      );
    }
    final text = await verifyPassword(password);
    if (text != null) {
      return ManualPasswordAttemptResult(
        outcome: ManualPasswordOutcome.succeeded,
        text: text,
      );
    }
  }
  return const ManualPasswordAttemptResult(
    outcome: ManualPasswordOutcome.attemptsExhausted,
  );
}

/// Service for detecting and trying common PDF passwords used by banks
class PdfPasswordDetectionService {
  ManualPasswordOutcome? lastManualPasswordOutcome;

  /// Common password patterns used by different banks
  static final Map<String, List<String>> bankPasswordPatterns = {
    'sbi': [
      'dob_ddmmyyyy',
      'dob_yyyymmdd',
      'dob_ddmmyy',
      'last4_card',
      'firstname_lastname',
      'lastname_firstname',
    ],
    'hdfc': [
      'dob_ddmmyyyy',
      'dob_yyyymmdd',
      'last4_card',
      'pan_last4',
      'firstname_dob',
    ],
    'icici': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'mobile_last4'],
    'axis': [
      'dob_ddmmyyyy',
      'dob_yyyymmdd',
      'last4_card',
      'firstname_lastname',
    ],
    'kotak': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card'],
  };

  /// Extract password hints and user data from email content
  Map<String, dynamic> extractPasswordHints({
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    String? userName,
    String? fileName,
  }) {
    final hints = <String, dynamic>{};

    hints['userName'] = userName ?? _extractNameFromEmail(userEmail);
    hints['userEmail'] = userEmail;

    final content = '$emailSubject $emailBody';
    final contentLower = content.toLowerCase();

    final explicitPassword = _extractExplicitPasswordFromContent(
      content,
      contentLower,
      hints,
    );
    if (explicitPassword != null) {
      hints['explicitPassword'] = explicitPassword;
    }

    final passwordFormat = _extractPasswordFormatInstruction(
      contentLower,
      hints,
    );
    if (passwordFormat != null) {
      hints['passwordFormat'] = passwordFormat;
    }

    if (fileName != null) {
      final cardNumbers = _extractCardNumberFromFilename(fileName);
      if (cardNumbers.isNotEmpty) {
        hints['cardNumbersFromFile'] = cardNumbers;
      }
    }

    _extractDataBasedOnFormat(content, contentLower, hints);

    return hints;
  }

  String? _extractExplicitPasswordFromContent(
    String content,
    String contentLower,
    Map<String, dynamic> hints,
  ) {
    final explicitPatterns = [
      RegExp(
        r'password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})',
        caseSensitive: false,
      ),
      RegExp(r'the password is\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'password:\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(
        r'access password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})',
        caseSensitive: false,
      ),
      RegExp(r'pin\s*(?:is|:)\s*([0-9]{4,8})', caseSensitive: false),
      RegExp(r'the pin is\s*([0-9]{4,8})', caseSensitive: false),
      RegExp(
        r'access code\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})',
        caseSensitive: false,
      ),
      RegExp(
        r'document password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in explicitPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        return match.group(1)!;
      }
    }

    return null;
  }

  String? _extractPasswordFormatInstruction(
    String contentLower,
    Map<String, dynamic> hints,
  ) {
    final formatPatterns = [
      RegExp(
        r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyyyy|dd\s*mm\s*yyyy)',
        caseSensitive: false,
      ),
      RegExp(
        r'password.*?(?:dob|date\s*of\s*birth).*?(?:yyyymmdd|yyyy\s*mm\s*dd)',
        caseSensitive: false,
      ),
      RegExp(
        r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyy|dd\s*mm\s*yy)',
        caseSensitive: false,
      ),
      RegExp(
        r'password.*?(?:dob|date\s*of\s*birth).*?(?:mmddyyyy|mm\s*dd\s*yyyy)',
        caseSensitive: false,
      ),
      RegExp(
        r'password.*?last\s*4\s*digits.*?(?:card|account)',
        caseSensitive: false,
      ),
      RegExp(r'password.*?last\s*4\s*digits.*?mobile', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?pan', caseSensitive: false),
      RegExp(r'password.*?(?:first\s*name|given\s*name)', caseSensitive: false),
      RegExp(r'password.*?(?:last\s*name|surname)', caseSensitive: false),
      RegExp(r'password.*?full\s*name', caseSensitive: false),
      RegExp(r'password.*?(?:ddmm|dd\s*mm)', caseSensitive: false),
      RegExp(r'password.*?(?:mmyy|mm\s*yy)', caseSensitive: false),
    ];

    for (final pattern in formatPatterns) {
      final match = pattern.firstMatch(contentLower);
      if (match != null) {
        return match.group(0)!;
      }
    }

    if (contentLower.contains('ddmmyyyy') ||
        contentLower.contains('dd mm yyyy')) {
      return 'dob_ddmmyyyy';
    }
    if (contentLower.contains('yyyymmdd') ||
        contentLower.contains('yyyy mm dd')) {
      return 'dob_yyyymmdd';
    }
    if (contentLower.contains('ddmmyy') || contentLower.contains('dd mm yy')) {
      return 'dob_ddmmyy';
    }
    if (contentLower.contains('mmddyyyy') ||
        contentLower.contains('mm dd yyyy')) {
      return 'dob_mmddyyyy';
    }

    return null;
  }

  void _extractDataBasedOnFormat(
    String content,
    String contentLower,
    Map<String, dynamic> hints,
  ) {
    final format = hints['passwordFormat'] as String?;

    if (format != null) {
      if (format.contains('name')) {
        hints['nameVariations'] = _extractNameVariations(
          hints['userName'] as String? ?? '',
        );
      }
    }
  }

  List<String> _extractNameVariations(String fullName) {
    final variations = <String>[];
    final nameParts = fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();

    if (nameParts.isNotEmpty) {
      final firstName = nameParts[0].toLowerCase();
      final lastName = nameParts.length > 1 ? nameParts.last.toLowerCase() : '';

      variations.add(firstName);
      variations.add(lastName);
      variations.add(fullName.toLowerCase().replaceAll(' ', ''));

      if (lastName.isNotEmpty) {
        variations.add('$firstName$lastName');
        variations.add('$lastName$firstName');
        variations.add('$firstName.$lastName');
        variations.add('$lastName.$firstName');
      }
    }
    return variations;
  }

  /// Generate possible passwords based on bank and extracted hints
  List<String> generatePasswordCandidates({
    required String bankName,
    required Map<String, dynamic> hints,
    Map<String, dynamic>? userProfile,
  }) {
    final passwords = <String>[];

    final userName = hints['userName'] as String? ?? '';
    final nameParts = userName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0].toLowerCase() : '';
    final lastName = nameParts.length > 1 ? nameParts.last.toLowerCase() : '';

    final nameDataCombinations = _generateNameDateCombinations(
      userName,
      userProfile,
    );
    passwords.addAll(nameDataCombinations);

    if (hints.containsKey('explicitPassword')) {
      passwords.insert(0, hints['explicitPassword'] as String);
    }

    final shortName = firstName.length >= 4
        ? firstName.substring(0, 4)
        : firstName;
    final commonPasswords = <String>[shortName, lastName];
    passwords.addAll(commonPasswords);

    final uniquePasswords = passwords
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
    return uniquePasswords;
  }

  /// Try to open PDF with different passwords
  Future<Map<String, dynamic>?> tryOpenPdfWithPasswords({
    required Uint8List pdfBytes,
    required List<String> passwords,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    for (int i = 0; i < passwords.length; i++) {
      final password = passwords[i];

      try {
        final document = PdfDocument(inputBytes: pdfBytes, password: password);
        ParsingLogger.summary(
          'Password: PDF decrypted successfully using candidate ${i + 1}/${passwords.length}',
        );

        if (bankName != null && userEmail != null) {
          await PasswordLearningService.storeSuccessfulPassword(
            bankName: bankName,
            password: password,
            userEmail: userEmail,
            fileName: fileName,
            userProfile: userProfile,
          );
        }
        return {'document': document, 'password': password};
      } catch (e) {
        continue;
      }
    }

    ParsingLogger.warning(
      'Password: None of the ${passwords.length} automatic candidates decrypted the PDF.',
    );
    return null;
  }

  /// Try to open PDF with a manually provided password
  Future<String?> tryManualPassword({
    required Uint8List pdfBytes,
    required String password,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    try {
      final document = PdfDocument(inputBytes: pdfBytes, password: password);
      final textExtractor = PdfTextExtractor(document);
      final text = textExtractor.extractText();
      document.dispose();
      ParsingLogger.summary(
        'Password: PDF decrypted successfully using manual password input',
      );

      if (bankName != null && userEmail != null) {
        await PasswordLearningService.storeSuccessfulPassword(
          bankName: bankName,
          password: password,
          userEmail: userEmail,
          fileName: fileName,
          userProfile: userProfile,
        );
      }

      return text;
    } catch (e) {
      return null;
    }
  }

  /// Extract password hints from email content and try to unlock PDF
  Future<String?> findPasswordAndExtractText({
    required Uint8List pdfBytes,
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    required String bankName,
    String? userName,
    Map<String, dynamic>? userProfile,
    String? fileName,
    Future<String?> Function(int attempt, int maxAttempts)?
    onManualPasswordRequired,
  }) async {
    try {
      lastManualPasswordOutcome = null;

      try {
        final document = PdfDocument(inputBytes: pdfBytes);
        final textExtractor = PdfTextExtractor(document);
        final text = textExtractor.extractText();
        document.dispose();
        ParsingLogger.summary('Password: PDF opened without password');
        return text;
      } catch (e) {
        // PDF is encrypted, continue with password detection
      }

      final hints = extractPasswordHints(
        emailSubject: emailSubject,
        emailBody: emailBody,
        userEmail: userEmail,
        userName: userName,
        fileName: fileName,
      );

      final learnedPasswords =
          await PasswordLearningService.getLearnedPasswordCandidates(
            bankName: bankName,
            userEmail: userEmail,
            userProfile: userProfile,
            fileName: fileName,
          );

      final passwords = generatePasswordCandidates(
        bankName: bankName,
        hints: hints,
        userProfile: userProfile,
      );

      final allPasswords = [...learnedPasswords, ...passwords];
      final uniquePasswords = allPasswords.toSet().toList();

      final result = await tryOpenPdfWithPasswords(
        pdfBytes: pdfBytes,
        passwords: uniquePasswords,
        bankName: bankName,
        userEmail: userEmail,
        fileName: fileName,
        userProfile: userProfile,
      );
      if (result != null) {
        final document = result['document'] as PdfDocument;
        try {
          final textExtractor = PdfTextExtractor(document);
          final text = textExtractor.extractText();
          document.dispose();
          return text;
        } catch (textError) {
          ParsingLogger.error('PDF text extraction failed', textError);
          document.dispose();
          return null;
        }
      }

      if (onManualPasswordRequired != null) {
        ParsingLogger.summary(
          'Password: Automatic decryption failed. Requesting manual password input...',
        );

        try {
          final manualResult = await runManualPasswordAttempts(
            requestPassword: (attempt, maxAttempts) async {
              ParsingLogger.summary(
                'Password: Manual input attempt $attempt/$maxAttempts for $bankName',
              );
              return onManualPasswordRequired(attempt, maxAttempts);
            },
            verifyPassword: (manualPassword) async {
              ParsingLogger.summary(
                'Password: Manual password received, testing decryption...',
              );
              return tryManualPassword(
                pdfBytes: pdfBytes,
                password: manualPassword,
                bankName: bankName,
                userEmail: userEmail,
                fileName: fileName,
                userProfile: userProfile,
              );
            },
          );
          lastManualPasswordOutcome = manualResult.outcome;
          if (manualResult.outcome == ManualPasswordOutcome.succeeded) {
            ParsingLogger.summary(
              'Password: Manual password verification succeeded.',
            );
            return manualResult.text;
          }
          if (manualResult.outcome == ManualPasswordOutcome.cancelled) {
            ParsingLogger.warning(
              'Password: Manual password entry cancelled by user',
            );
          } else {
            ParsingLogger.warning(
              'Password: All manual password attempts exhausted',
            );
          }
        } catch (e) {
          ParsingLogger.error('Password: Error during manual decryption', e);
        }
      } else {
        ParsingLogger.warning(
          'Password: No manual password callback available',
        );
      }

      return null;
    } catch (error) {
      ParsingLogger.error('Password detection error', error);
      return null;
    }
  }

  String _extractNameFromEmail(String email) {
    final localPart = email.split('@')[0];
    return localPart.replaceAll(RegExp(r'[^a-zA-Z\s]'), ' ').trim();
  }

  /// Generate name and date combination passwords
  List<String> _generateNameDateCombinations(
    String fullName,
    Map<String, dynamic>? userProfile,
  ) {
    final combinations = <String>[];

    if (fullName.isEmpty) return combinations;

    final nameParts = fullName
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();
    if (nameParts.isEmpty) return combinations;
    final firstName = nameParts[0];
    final firstNameLower = firstName.toLowerCase();
    final firstNameUpper = firstName.toUpperCase();

    final shortNameLower = firstName.length >= 4
        ? firstName.toLowerCase().substring(0, 4)
        : firstNameLower;
    final shortNameUpper = firstName.length >= 4
        ? firstName.toUpperCase().substring(0, 4)
        : firstNameUpper;

    if (userProfile != null && userProfile.containsKey('birthday')) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;

      final ddmm = birthday['ddmm'] ?? '';
      final ddmmyyyy = birthday['ddmmyyyy'] ?? '';
      final yyyymmdd = birthday['yyyymmdd'] ?? '';
      final ddmmyy = birthday['ddmmyy'] ?? '';

      if (ddmm.isNotEmpty) {
        combinations.add('$shortNameLower$ddmm');
        combinations.add('$shortNameUpper$ddmm');
        combinations.add(ddmm);
      }

      if (ddmmyyyy.isNotEmpty) {
        combinations.add('$shortNameLower$ddmmyyyy');
        combinations.add('$shortNameUpper$ddmmyyyy');
        combinations.add(ddmmyyyy);
      }

      if (ddmmyy.isNotEmpty) {
        combinations.add('$shortNameLower$ddmmyy');
        combinations.add('$shortNameUpper$ddmmyy');
        combinations.add(ddmmyy);
      }

      if (yyyymmdd.isNotEmpty) {
        combinations.add('$shortNameLower$yyyymmdd');
        combinations.add('$shortNameUpper$yyyymmdd');
        combinations.add(yyyymmdd);
      }
    }

    return combinations.toSet().toList();
  }

  /// Extract credit card numbers from filename
  List<String> _extractCardNumberFromFilename(String fileName) {
    final cardNumbers = <String>[];

    final sbiPattern = RegExp(r'(\d{12,20})_\d{8}\.pdf$');
    final sbiMatch = sbiPattern.firstMatch(fileName);
    if (sbiMatch != null) {
      final fullCardNumber = sbiMatch.group(1)!;
      final last4 = fullCardNumber.substring(fullCardNumber.length - 4);
      cardNumbers.add(last4);
    }

    final patterns = [
      RegExp(r'[xX]{4}(\d{4})', caseSensitive: false),
      RegExp(r'(?:ending|last|card)[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'(\d{4})\.pdf$', caseSensitive: false),
      RegExp(r'card[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'statement[\s\-_]*(\d{4})', caseSensitive: false),
      RegExp(r'\b(\d{4})\b'),
    ];
    for (final pattern in patterns) {
      final matches = pattern.allMatches(fileName);
      for (final match in matches) {
        if (match.group(1) != null) {
          final last4 = match.group(1)!;
          if (!cardNumbers.contains(last4)) {
            cardNumbers.add(last4);
          }
        }
      }
    }

    return cardNumbers;
  }
}
