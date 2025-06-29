import 'dart:typed_data';
import 'package:cardcompass/shared/models/transaction.dart';

/// Helper class for statement parsing results
class StatementParsingResult {
  final String bankName;
  final DateTime statementDate;
  final List<Transaction> transactions;
  final Uint8List originalPdfData;
  final String emailMessageId;
  final bool processingSuccess;
  
  // Additional email-related properties
  final String? emailSubject;
  final String? emailSender;
  
  // Additional statement-related properties
  final DateTime? dueDate;
  final double? totalAmountDue;
  final double? minimumAmountDue;
  final double? availableCredit;
  final double? rewardsEarned;
  final String? cardVariantName;

  StatementParsingResult({
    required this.bankName,
    required this.statementDate,
    required this.transactions,
    required this.originalPdfData,
    required this.emailMessageId,
    required this.processingSuccess,
    this.emailSubject,
    this.emailSender,
    this.dueDate,
    this.totalAmountDue,
    this.minimumAmountDue,
    this.availableCredit,
    this.rewardsEarned,
    this.cardVariantName,
  });
}

/// Helper class for PDF attachment information
class PdfAttachment {
  final String attachmentId;
  final String filename;
  final int size;

  PdfAttachment({
    required this.attachmentId,
    required this.filename,
    required this.size,
  });
}
