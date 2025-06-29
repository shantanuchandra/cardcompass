import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/pdf_password_detection_service.dart';

void main() {
  test('Test password generation with first 4 chars of name + date', () async {
    final service = PdfPasswordDetectionService();
    
    // Test the name-date combination generation
    final userProfile = {
      'birthday': {
        'day': '02',
        'month': '12',
        'year': '1990',
        'ddmmyyyy': '02121990',
        'yyyymmdd': '19901202',
        'ddmmyy': '021290',
        'ddmm': '0212',
        'mmddyyyy': '12021990',
        'yymmdd': '901202',
      }
    };
    
    final hints = {
      'userName': 'shantanu',
      'userEmail': 'shantanu.msp@gmail.com',
    };
    
    // Generate password candidates
    final passwords = service.generatePasswordCandidates(
      bankName: 'HDFC', 
      hints: hints, 
      userProfile: userProfile,
    );
    
    print('\n=== GENERATED PASSWORD CANDIDATES ===');
    for (int i = 0; i < passwords.length; i++) {
      print('${i + 1}. "${passwords[i]}"');
    }
    
    // Check that the required combinations are present
    expect(passwords.contains('shan0212'), isTrue, reason: 'Should contain shan0212');
    expect(passwords.contains('SHAN0212'), isTrue, reason: 'Should contain SHAN0212');
    expect(passwords.contains('0212'), isTrue, reason: 'Should contain 0212');
    expect(passwords.contains('02121990'), isTrue, reason: 'Should contain 02121990');
    expect(passwords.contains('shan02121990'), isTrue, reason: 'Should contain shan02121990');
    expect(passwords.contains('SHAN02121990'), isTrue, reason: 'Should contain SHAN02121990');
    
    print('\n✅ All required password patterns are generated correctly!');
    print('✅ First 4 chars combinations: shan0212, SHAN0212');
    print('✅ Date-only combinations: 0212, 02121990');
    print('✅ Full name+date combinations: shan02121990, SHAN02121990');
  });
}
