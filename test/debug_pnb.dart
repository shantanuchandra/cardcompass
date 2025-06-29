import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';

void main() {
  test('Debug PNB PDF Structure', () async {
    try {
      final file = File('assets/2231832797_PNB.pdf');
      final bytes = await file.readAsBytes();
      
      // Try with password
      final document = PdfDocument(inputBytes: bytes, password: 'shan02121990');
      
      for (int i = 0; i < document.pages.count; i++) {
        print('\n=== PAGE ${i + 1} ===');
        final extractor = PdfTextExtractor(document);
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        final lines = text.split('\n');
        
        // Print all lines with line numbers to understand structure
        for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          final line = lines[lineIndex].trim();
          if (line.isNotEmpty) {
            print('Line ${lineIndex + 1}: $line');
          }
        }
      }
      
      document.dispose();
    } catch (e) {
      print('Error reading PNB PDF: $e');
    }
  });
}
