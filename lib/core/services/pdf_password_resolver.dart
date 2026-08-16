import 'dart:typed_data';
import '../../app.dart' show navigatorKey;
import 'pdf_password_detection_service.dart';
import 'password_input_service.dart';
import 'simple_birthday_input_service.dart';
import 'user_profile_service.dart';

/// Orchestrates unlocking a password-protected statement PDF: cached
/// password -> DB date-of-birth -> Google People API date-of-birth ->
/// DOB-entry dialog -> generated bank-pattern candidates -> manual password
/// dialog (2 attempts). Returns the extracted text, or null if every step
/// fails.
class PdfPasswordResolver {
  final PdfPasswordDetectionService _detectionService =
      PdfPasswordDetectionService();

  ManualPasswordOutcome? get lastManualPasswordOutcome =>
      _detectionService.lastManualPasswordOutcome;

  bool get manualAttemptsExhausted =>
      lastManualPasswordOutcome == ManualPasswordOutcome.attemptsExhausted;

  Future<String?> extractText({
    required Uint8List pdfBytes,
    required String bankName,
    required String userId,
    required String userEmail,
    required String userName,
    required String googleAccessToken,
    String? fileName,
    String emailSubject = '',
    String emailBody = '',
  }) async {
    Map<String, dynamic>? userProfile;

    var dob = await UserProfileService.getDateOfBirth(userId);

    if (dob == null && googleAccessToken.isNotEmpty) {
      dob = await UserProfileService.getGoogleBirthday(googleAccessToken);
      if (dob != null) {
        await UserProfileService.storeDateOfBirth(userId, dob);
      }
    }

    if (dob == null) {
      final context = navigatorKey.currentContext;
      dob = await SimpleBirthdayInputService.requestBirthdayInput(
        context: context,
        userId: userId,
        reason: 'Unlocking your $bankName statement PDF',
      );
      if (dob != null) {
        await UserProfileService.storeDateOfBirth(userId, dob);
      }
    }

    if (dob != null) {
      userProfile = {
        'birthday': SimpleBirthdayInputService.formatBirthdayForPasswords(dob),
      };
    }

    return _detectionService.findPasswordAndExtractText(
      pdfBytes: pdfBytes,
      emailSubject: emailSubject,
      emailBody: emailBody,
      userEmail: userEmail,
      bankName: bankName,
      userName: userName,
      userProfile: userProfile,
      fileName: fileName,
      onManualPasswordRequired: (attempt, maxAttempts, hint) =>
          PasswordInputService.requestPassword(
            bankName,
            attempt: attempt,
            maxAttempts: maxAttempts,
            hint: hint,
          ),
    );
  }
}
