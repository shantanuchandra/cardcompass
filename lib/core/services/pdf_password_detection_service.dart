import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:cardcompass/core/services/password_input_service.dart';
import 'package:cardcompass/core/services/password_learning_service.dart';

/// Service for detecting and trying common PDF passwords used by banks
class PdfPasswordDetectionService {
  
  /// Common password patterns used by different banks
  static final Map<String, List<String>> bankPasswordPatterns = {
    'sbi': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'dob_ddmmyy', 'last4_card', 'firstname_lastname', 'lastname_firstname'],
    'hdfc': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'pan_last4', 'firstname_dob'],
    'icici': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'mobile_last4'],
    'axis': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card', 'firstname_lastname'],
    'kotak': ['dob_ddmmyyyy', 'dob_yyyymmdd', 'last4_card'],
  };  /// Extract password hints and user data from email content
  Map<String, dynamic> extractPasswordHints({
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    String? userName,
    String? fileName,
  }) {
    final hints = <String, dynamic>{};
    
    // Extract user name from email or provided name
    hints['userName'] = userName ?? _extractNameFromEmail(userEmail);
    hints['userEmail'] = userEmail;
      // Combine subject and body for analysis
    final content = '$emailSubject $emailBody';
    final contentLower = content.toLowerCase();
    
    // Look for explicit password instructions and hints
    final explicitPassword = _extractExplicitPasswordFromContent(content, contentLower, hints);
    if (explicitPassword != null) {
      hints['explicitPassword'] = explicitPassword;
    }
      
    // Look for password format instructions
    final passwordFormat = _extractPasswordFormatInstruction(contentLower, hints);
    if (passwordFormat != null) {
      hints['passwordFormat'] = passwordFormat;
    }
    
    // Extract credit card number from filename (especially for SBI)
    if (fileName != null) {
      final cardNumbers = _extractCardNumberFromFilename(fileName);
      if (cardNumbers.isNotEmpty) {
        hints['cardNumbersFromFile'] = cardNumbers;
      }
    }
      
    // Extract specific data based on found format
    _extractDataBasedOnFormat(content, contentLower, hints);
    
    return hints;
  }

  /// Extract explicit password mentioned in email content
  String? _extractExplicitPasswordFromContent(String content, String contentLower, Map<String, dynamic> hints) {
    // Common explicit password patterns
    final explicitPatterns = [
      // Direct password mentions
      RegExp(r'password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'the password is\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'password:\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'access password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      
      // PIN mentions
      RegExp(r'pin\s*(?:is|:)\s*([0-9]{4,8})', caseSensitive: false),
      RegExp(r'the pin is\s*([0-9]{4,8})', caseSensitive: false),
      
      // Access code mentions
      RegExp(r'access code\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
      RegExp(r'document password\s*(?:is|:)\s*([a-zA-Z0-9]{4,12})', caseSensitive: false),
    ];
    
    for (final pattern in explicitPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        return match.group(1)!;
      }
    }
    
    return null;
  }

  /// Extract password format instruction from email
  String? _extractPasswordFormatInstruction(String contentLower, Map<String, dynamic> hints) {
    // Common password format instructions
    final formatPatterns = [
      // Date of birth formats
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyyyy|dd\s*mm\s*yyyy)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:yyyymmdd|yyyy\s*mm\s*dd)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:ddmmyy|dd\s*mm\s*yy)', caseSensitive: false),
      RegExp(r'password.*?(?:dob|date\s*of\s*birth).*?(?:mmddyyyy|mm\s*dd\s*yyyy)', caseSensitive: false),
      
      // Last 4 digits patterns
      RegExp(r'password.*?last\s*4\s*digits.*?(?:card|account)', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?mobile', caseSensitive: false),
      RegExp(r'password.*?last\s*4\s*digits.*?pan', caseSensitive: false),
      
      // Name patterns
      RegExp(r'password.*?(?:first\s*name|given\s*name)', caseSensitive: false),
      RegExp(r'password.*?(?:last\s*name|surname)', caseSensitive: false),
      RegExp(r'password.*?full\s*name', caseSensitive: false),
      
      // Common specific instructions
      RegExp(r'password.*?(?:ddmm|dd\s*mm)', caseSensitive: false),
      RegExp(r'password.*?(?:mmyy|mm\s*yy)', caseSensitive: false),
    ];
    
    for (final pattern in formatPatterns) {
      final match = pattern.firstMatch(contentLower);
      if (match != null) {
        return match.group(0)!; // Return the full matched instruction
      }
    }
    
    // Check for specific format mentions
    if (contentLower.contains('ddmmyyyy') || contentLower.contains('dd mm yyyy')) {
      return 'dob_ddmmyyyy';
    }
    if (contentLower.contains('yyyymmdd') || contentLower.contains('yyyy mm dd')) {
      return 'dob_yyyymmdd';
    }
    if (contentLower.contains('ddmmyy') || contentLower.contains('dd mm yy')) {
      return 'dob_ddmmyy';
    }
    if (contentLower.contains('mmddyyyy') || contentLower.contains('mm dd yyyy')) {
      return 'dob_mmddyyyy';
    }
    
    return null;  }
  
  /// Extract specific data based on identified password format
  void _extractDataBasedOnFormat(String content, String contentLower, Map<String, dynamic> hints) {
    // Only look for explicit password format instructions and hints
    // Do not extract DOBs, mobile numbers, etc. from email content    // The actual password detection logic should rely on user profile data
    
    final format = hints['passwordFormat'] as String?;
    
    if (format != null) {
      if (format.contains('name')) {
        hints['nameVariations'] = _extractNameVariations(hints['userName'] as String? ?? '');
      }
      // Note: We don't extract dates, mobile numbers, or PAN numbers from emails
      // These should come from user profile data or be explicitly stated
    }
    
    // Note: Four-digit numbers are no longer extracted from emails as per user requirement
  }  /// Extract name variations from a full name
  List<String> _extractNameVariations(String fullName) {
    final variations = <String>[];
    final nameParts = fullName.split(' ').where((part) => part.isNotEmpty).toList();
    
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
  }) {    final passwords = <String>[];
    
      final userName = hints['userName'] as String? ?? '';    final nameParts = userName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0].toLowerCase() : '';
    final lastName = nameParts.length > 1 ? nameParts.last.toLowerCase() : '';
    
    // These will be populated from user profile data only
    final possibleDOBs = <String>[];    // PRIORITY 1: Add specific name+date combinations (highest priority)
    final nameDataCombinations = _generateNameDateCombinations(userName, userProfile);
    passwords.addAll(nameDataCombinations);
    
    // PRIORITY 2: Add explicit password from email if found
    if (hints.containsKey('explicitPassword')) {
      passwords.insert(0, hints['explicitPassword'] as String);
    }
      
    // Add birthday passwords from user profile (PRIORITY 3)
    if (userProfile != null && userProfile.containsKey('birthday')) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;
      possibleDOBs.insert(0, birthday['ddmmyyyy'] ?? '');
      possibleDOBs.insert(0, birthday['yyyymmdd'] ?? '');
      possibleDOBs.insert(0, birthday['ddmmyy'] ?? '');
      possibleDOBs.insert(0, birthday['ddmm'] ?? '');
    }
    
    // Add some common variations (minimal set)
    final shortName = firstName.length >= 4 ? firstName.substring(0, 4) : firstName;
    final commonPasswords = <String>[
      shortName, lastName,
    ];
    passwords.addAll(commonPasswords);    
    
    // Remove duplicates and empty strings
    final uniquePasswords = passwords.where((p) => p.isNotEmpty).toSet().toList();
    return uniquePasswords;
  }  /// Try to open PDF with different passwords
  Future<Map<String, dynamic>?> tryOpenPdfWithPasswords({
    required Uint8List pdfBytes,
    required List<String> passwords,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,  }) async {
    
    for (int i = 0; i < passwords.length; i++) {
      final password = passwords[i];      // Don't print the actual password being tested to avoid showing failed attempts
      // print('Testing password ${i + 1}/${passwords.length}...');
      
      try {
        final document = PdfDocument(inputBytes: pdfBytes, password: password);
        // If we get here, the password worked        print('PASSWORD: "$password"');
        
        // Store the successful password for learning
        if (bankName != null && userEmail != null) {
          await PasswordLearningService.storeSuccessfulPassword(
            bankName: bankName,
            password: password,
            userEmail: userEmail,
            fileName: fileName,
            userProfile: userProfile,
          );
        }
          return {
          'document': document,
          'password': password,
        };
      } catch (e) {
        // Try next password
        // print('❌ Failed with password: "$password"');
        continue;
      }
    }
    
    print('⚠️ No password worked out of ${passwords.length} attempts');
    return null;  }

  /// Try to open PDF with a manually provided password
  Future<String?> tryManualPassword({
    required Uint8List pdfBytes,
    required String password,
    String? bankName,
    String? userEmail,
    String? fileName,
    Map<String, dynamic>? userProfile,
  }) async {
    // Don't print the password being tested to avoid showing failed attempts
    
    try {
      final document = PdfDocument(inputBytes: pdfBytes, password: password);
      final textExtractor = PdfTextExtractor(document);
      final text = textExtractor.extractText();      document.dispose();
      print('PASSWORD: "$password"');
      
      // Store the successful manual password for learning
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
      // Don't print the failed password attempt
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
    Future<String?> Function()? onManualPasswordRequired,  }) async {
    try {
      // Reset password attempt tracking for new PDF
      PasswordInputService.resetAttempts();
      
      // First try without password
      try {
        final document = PdfDocument(inputBytes: pdfBytes);
        final textExtractor = PdfTextExtractor(document);
        final text = textExtractor.extractText();
        document.dispose();
        print('PDF opened without password');
        return text;
      } catch (e) {
        // PDF is encrypted, continue with password detection
      }        // Extract password hints from email
      final hints = extractPasswordHints(
        emailSubject: emailSubject,
        emailBody: emailBody,
        userEmail: userEmail,        userName: userName,
        fileName: fileName,
      );
      
      // Get learned password candidates first (highest priority)
      final learnedPasswords = await PasswordLearningService.getLearnedPasswordCandidates(
        bankName: bankName,
        userEmail: userEmail,
        userProfile: userProfile,
        fileName: fileName,
      );
        
      // Generate password candidates (including user profile birthday)
      final passwords = generatePasswordCandidates(
        bankName: bankName,
        hints: hints,
        userProfile: userProfile,
      );
      
      // Combine learned passwords with generated ones (learned passwords get priority)
      final allPasswords = [...learnedPasswords, ...passwords];
      final uniquePasswords = allPasswords.toSet().toList(); // Remove duplicates
        
      // Try to open PDF with generated passwords
      final result = await tryOpenPdfWithPasswords(
        pdfBytes: pdfBytes,
        passwords: uniquePasswords,
        bankName: bankName,
        userEmail: userEmail,
        fileName: fileName,
        userProfile: userProfile,
      );      if (result != null) {
        final document = result['document'] as PdfDocument;
          // print('Extracting text from PDF unlocked with password: $password');
        try {
          final textExtractor = PdfTextExtractor(document);
          final text = textExtractor.extractText();
          document.dispose();
          return text;
        } catch (textError) {
          print('❌ Text extraction failed: $textError');
          document.dispose();
          return null;
        }
      }      // Try to get manual password from user if callback is provided
      if (onManualPasswordRequired != null) {
        print('🔐 Automatic passwords failed, requesting manual input...');
        
        // Allow up to 2 manual password attempts as specified
        for (int attempt = 1; attempt <= 2; attempt++) {
          try {
            print('📝 Manual password attempt $attempt/2 for $bankName');
            final manualPassword = await onManualPasswordRequired();
            
            if (manualPassword != null && manualPassword.isNotEmpty) {
              print('🔑 Manual password received, testing...');
              final result = await tryManualPassword(
                pdfBytes: pdfBytes,
                password: manualPassword,
                bankName: bankName,
                userEmail: userEmail,
                fileName: fileName,
                userProfile: userProfile,
              );
              if (result != null) {
                print('✅ Manual password worked!');
                return result;
              } else {
                print('❌ Manual password attempt $attempt failed');
              }
            } else {
              print('❌ No manual password provided, user cancelled');
              break; // User cancelled
            }
          } catch (e) {
            print('❌ Error during manual password attempt: $e');
            break; // Error occurred
          }
        }
        
        print('⚠️ All manual password attempts exhausted');
      } else {
        print('⚠️ No manual password callback available');
      }
      
      return null;
      
    } catch (error) {
      print('Error in password detection: $error');
      return null;
    }
  }

  String _extractNameFromEmail(String email) {
    // Extract name from email address before @
    final localPart = email.split('@')[0];
    return localPart.replaceAll(RegExp(r'[^a-zA-Z\s]'), ' ').trim();
  }

  /// Generate name and date combination passwords
  /// For example: 'Shantanu' + '02/12/1990' -> ['shan0212', '0212', 'shan02121990', '02121990', 'SHAN0212']
  /// Uses only short name variants (first 4 characters of the first name)
  List<String> _generateNameDateCombinations(String fullName, Map<String, dynamic>? userProfile) {
    final combinations = <String>[];
    
    if (fullName.isEmpty) return combinations;
    
    final nameParts = fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.isEmpty) return combinations;
      final firstName = nameParts[0];
    final firstNameLower = firstName.toLowerCase();
    final firstNameUpper = firstName.toUpperCase();
    
    // Also generate short name variants (first 4 characters)
    final shortNameLower = firstName.length >= 4 ? firstName.toLowerCase().substring(0, 4) : firstNameLower;
    final shortNameUpper = firstName.length >= 4 ? firstName.toUpperCase().substring(0, 4) : firstNameUpper;
    
    // Get birthday formats from user profile
    if (userProfile != null && userProfile.containsKey('birthday')) {
      final birthday = userProfile['birthday'] as Map<String, dynamic>;
      
      final ddmm = birthday['ddmm'] ?? '';  // 0212
      final ddmmyyyy = birthday['ddmmyyyy'] ?? '';  // 02121990
      final yyyymmdd = birthday['yyyymmdd'] ?? '';  // 19901202
      final ddmmyy = birthday['ddmmyy'] ?? '';  // 021290      // Generate the specific patterns requested
      if (ddmm.isNotEmpty) {
        // Pattern: shan0212, SHAN0212 (short name only)
        combinations.add('$shortNameLower$ddmm');
        combinations.add('$shortNameUpper$ddmm');
        
        // Just the date part: 0212
        combinations.add(ddmm);
      }
      
      if (ddmmyyyy.isNotEmpty) {
        // Pattern: shan02121990 (short name only)
        combinations.add('$shortNameLower$ddmmyyyy');
        combinations.add('$shortNameUpper$ddmmyyyy');
        
        // Just the full date: 02121990
        combinations.add(ddmmyyyy);
      }
      
      if (ddmmyy.isNotEmpty) {
        // Pattern: shan021290 (short name only)
        combinations.add('$shortNameLower$ddmmyy');
        combinations.add('$shortNameUpper$ddmmyy');
        
        // Just the short date: 021290
        combinations.add(ddmmyy);
      }
      
      if (yyyymmdd.isNotEmpty) {
        // Additional patterns with YYYY format (short name only)
        combinations.add('$shortNameLower$yyyymmdd');
        combinations.add('$shortNameUpper$yyyymmdd');
        combinations.add(yyyymmdd);
      }}
    
    // Remove duplicates and return
    return combinations.toSet().toList();  }
  
  /// Test method to verify password generation for specific cases
  /// This method can be called during debugging to ensure the password patterns work correctly
  Map<String, dynamic> testPasswordGeneration({
    required String firstName,
    required String dob, // Format: DD/MM/YYYY
    required String bankName,
  }) {
    print('=== TESTING PASSWORD GENERATION ===');
    print('First Name: $firstName');
    print('DOB: $dob');
    print('Bank: $bankName');
    
    // Parse DOB
    final dobParts = dob.split('/');
    if (dobParts.length != 3) {
      print('ERROR: Invalid DOB format. Expected DD/MM/YYYY');
      return {'error': 'Invalid DOB format'};
    }
    
    final day = dobParts[0].padLeft(2, '0');
    final month = dobParts[1].padLeft(2, '0');
    final year = dobParts[2];
    
    // Create user profile with birthday data
    final userProfile = {
      'birthday': {
        'day': day,
        'month': month,
        'year': year,
        'ddmmyyyy': '$day$month$year',      // 02121990
        'yyyymmdd': '$year$month$day',      // 19901202
        'ddmmyy': '$day$month${year.substring(2)}',  // 021290
        'ddmm': '$day$month',               // 0212
        'mmddyyyy': '$month$day$year',      // 12021990
        'yymmdd': '${year.substring(2)}$month$day',  // 901202
      }
    };
    
    // Create mock hints
    final hints = {
      'userName': firstName,
      'possibleDOBs': ['$day$month$year', '$year$month$day', '$day$month${year.substring(2)}'],
    };
    
    // Generate passwords using the main method
    final passwords = generatePasswordCandidates(
      bankName: bankName,
      hints: hints,
      userProfile: userProfile,
    );
    
    // Also test the specific name+date combinations
    final nameDateCombinations = _generateNameDateCombinations(firstName, userProfile);
      print('\n=== GENERATED PASSWORD CANDIDATES ===');
    passwords.forEach((pwd) => print('- $pwd'));
    
    // Only show name+date combinations that are NOT already in the main password list
    final uniqueNameDateCombinations = nameDateCombinations.where((pwd) => !passwords.contains(pwd)).toList();
    
    if (uniqueNameDateCombinations.isNotEmpty) {
      print('\n=== NAME+DATE COMBINATIONS (additional) ===');
      uniqueNameDateCombinations.forEach((pwd) => print('- $pwd'));
    } else {
      print('\n=== NAME+DATE COMBINATIONS ===');
      print('(All name+date combinations are already included in the password candidates above)');
    }
      // Check for the specific expected patterns
    final shortName = firstName.length >= 4 ? firstName.toLowerCase().substring(0, 4) : firstName.toLowerCase();
    final expectedPatterns = [
      '$shortName$day$month',                          // shan0212
      day + month,                                      // 0212
      '$shortName$day$month$year',                     // shan02121990
      '$day$month$year',                               // 02121990
      '${shortName.toUpperCase()}$day$month',          // SHAN0212
    ];
    
    print('\n=== CHECKING EXPECTED PATTERNS ===');
    final foundPatterns = <String>[];
    final missingPatterns = <String>[];
    
    for (final expected in expectedPatterns) {
      if (passwords.contains(expected) || nameDateCombinations.contains(expected)) {
        foundPatterns.add(expected);
        print('✓ FOUND: $expected');
      } else {
        missingPatterns.add(expected);
        print('✗ MISSING: $expected');
      }
    }
    
    final result = {
      'allPasswords': passwords,
      'nameDateCombinations': nameDateCombinations,
      'expectedPatterns': expectedPatterns,
      'foundPatterns': foundPatterns,
      'missingPatterns': missingPatterns,
      'success': missingPatterns.isEmpty,
    };
      print('\n=== TEST RESULT ===');    print('Success: ${result['success']}');
    print('Found ${foundPatterns.length}/${expectedPatterns.length} expected patterns');
    
    return result;
  }
    /// Extract credit card numbers from filename
  /// Looks for patterns like XXXX1234, ending digits, etc.
  List<String> _extractCardNumberFromFilename(String fileName) {
    final cardNumbers = <String>[];
    
    // PRIORITY 1: SBI-specific pattern: long number before underscore (e.g., 9391656461119329_08062025.pdf)
    final sbiPattern = RegExp(r'(\d{12,20})_\d{8}\.pdf$');
    final sbiMatch = sbiPattern.firstMatch(fileName);
    if (sbiMatch != null) {
      final fullCardNumber = sbiMatch.group(1)!;
      final last4 = fullCardNumber.substring(fullCardNumber.length - 4);
      cardNumbers.add(last4);
      print(' $fileName: SBI pattern found: Full number=$fullCardNumber, Last4=$last4');
    }
    
    // PRIORITY 2: Other common patterns in credit card statement filenames
    final patterns = [
      // Pattern like "XXXX1234", "xxxx1234"
      RegExp(r'[xX]{4}(\d{4})', caseSensitive: false),
      
      // Pattern like "ending1234", "last1234"
      RegExp(r'(?:ending|last|card)[\s\-_]*(\d{4})', caseSensitive: false),
      
      // Pattern like "1234.pdf" - standalone 4 digits before extension
      RegExp(r'(\d{4})\.pdf$', caseSensitive: false),
      
      // Pattern like "Card_1234_Statement"
      RegExp(r'card[\s\-_]*(\d{4})', caseSensitive: false),
      
      // Pattern like "Statement_1234"
      RegExp(r'statement[\s\-_]*(\d{4})', caseSensitive: false),
      
      // Any 4 digits that might be card last 4 (lowest priority)
      RegExp(r'\b(\d{4})\b'),
    ];
    for (final pattern in patterns) {
      final matches = pattern.allMatches(fileName);
      for (final match in matches) {
        if (match.group(1) != null) {
          final last4 = match.group(1)!;
          if (!cardNumbers.contains(last4)) { // Avoid duplicates
            cardNumbers.add(last4);
          }
        }
      }
    }
    
    return cardNumbers;
  }
  /// Generate SBI-specific passwords: DOB + last 4 digits of credit card
  /// Try multiple formats since SBI might use different combinations
}
