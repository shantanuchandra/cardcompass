import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/debug/sync_flow_debugger.dart';

void main() {
  group('SyncFlowDebugger', () {
    setUp(() {
      // Clear any previous session before each test
      SyncFlowDebugger.clear();
    });

    test('should start a debug session', () {
      SyncFlowDebugger.start('test-user-123');
      
      final steps = SyncFlowDebugger.getSteps();
      expect(steps, isEmpty); // No steps logged yet
    });

    test('should log steps with data', () {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logStep('TEST_STEP', 'Testing step logging', data: {
        'key1': 'value1',
        'key2': 42,
      });
      
      final steps = SyncFlowDebugger.getSteps();
      expect(steps.length, 1);
      expect(steps.first.stepName, 'TEST_STEP');
      expect(steps.first.message, 'Testing step logging');
      expect(steps.first.data?['key1'], 'value1');
      expect(steps.first.data?['key2'], 42);
    });

    test('should track step counts', () {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logStep('STEP_A', 'First A');
      SyncFlowDebugger.logStep('STEP_B', 'First B');
      SyncFlowDebugger.logStep('STEP_A', 'Second A');
      SyncFlowDebugger.logStep('STEP_A', 'Third A');
      
      final report = SyncFlowDebugger.generateReport();
      expect(report, contains('STEP_A'));
      expect(report, contains('3 times')); // STEP_A logged 3 times
    });

    test('should log errors', () {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logError('ERROR_STEP', 'Something went wrong');
      
      final errors = SyncFlowDebugger.getErrors();
      expect(errors.length, 1);
      expect(errors.first, contains('ERROR_STEP'));
      expect(errors.first, contains('Something went wrong'));
    });

    test('should time operations', () async {
      SyncFlowDebugger.start('test-user-123');
      
      final timer = SyncFlowDebugger.startTimer('Test Operation');
      
      // Simulate some work
      await Future.delayed(const Duration(milliseconds: 100));
      
      SyncFlowDebugger.endTimer('Test Operation', timer);
      
      final report = SyncFlowDebugger.generateReport();
      expect(report, contains('Timed Operations'));
      expect(report, contains('Test Operation'));
    });

    test('should generate comprehensive report', () {
      SyncFlowDebugger.start('test-user-123');
      
      // Simulate a sync flow
      SyncFlowDebugger.logStep('SYNC_STARTED', 'User initiated sync');
      SyncFlowDebugger.logStep('GMAIL_AUTH', 'Gmail authenticated');
      SyncFlowDebugger.logStep('EMAIL_FOUND', 'Found 3 emails', data: {'count': 3});
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Processing email 1');
      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF unlocked successfully');
      SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Stored 47 transactions', data: {'count': 47});
      
      final report = SyncFlowDebugger.generateReport();
      
      // Check report sections
      expect(report, contains('SYNC FLOW DEBUG REPORT'));
      expect(report, contains('Session Summary'));
      expect(report, contains('User ID: test-user-123'));
      expect(report, contains('Total Steps: 6'));
      expect(report, contains('Step Execution Counts'));
      expect(report, contains('Execution Timeline'));
      expect(report, contains('Key Metrics'));
    });

    test('should filter steps by name', () {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Email 1');
      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'Unlocked');
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Email 2');
      SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Email 3');
      
      final emailSteps = SyncFlowDebugger.getStepsByName('EMAIL_PROCESSED');
      expect(emailSteps.length, 3);
      
      final pdfSteps = SyncFlowDebugger.getStepsByName('PDF_UNLOCKED');
      expect(pdfSteps.length, 1);
    });

    test('should clear session data', () {
      SyncFlowDebugger.start('test-user-123');
      SyncFlowDebugger.logStep('TEST', 'Test step');
      
      expect(SyncFlowDebugger.getSteps().isNotEmpty, true);
      
      SyncFlowDebugger.clear();
      
      expect(SyncFlowDebugger.getSteps().isEmpty, true);
      expect(SyncFlowDebugger.getErrors().isEmpty, true);
    });

    test('should handle multiple errors', () {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logError('PDF_UNLOCK', 'Failed to unlock PDF 1');
      SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF 2 success');
      SyncFlowDebugger.logError('GEMINI_PARSE', 'API timeout');
      
      final errors = SyncFlowDebugger.getErrors();
      expect(errors.length, 2);
      
      final report = SyncFlowDebugger.generateReport();
      expect(report, contains('Errors: 2'));
      expect(report, contains('Errors Encountered'));
    });

    test('mixin should work correctly', () {
      final testService = TestServiceWithMixin();
      
      SyncFlowDebugger.start('test-user-123');
      
      testService.performOperation();
      
      final steps = SyncFlowDebugger.getSteps();
      expect(steps.any((s) => s.stepName == 'OPERATION_START'), true);
      expect(steps.any((s) => s.stepName == 'OPERATION_END'), true);
    });

    test('should measure elapsed time correctly', () async {
      SyncFlowDebugger.start('test-user-123');
      
      SyncFlowDebugger.logStep('STEP_1', 'First step');
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      SyncFlowDebugger.logStep('STEP_2', 'Second step');
      
      final steps = SyncFlowDebugger.getSteps();
      expect(steps.length, 2);
      
      // Second step should have higher elapsed time than first
      expect(steps[1].elapsedTime.inMilliseconds > steps[0].elapsedTime.inMilliseconds, true);
    });

    test('should generate key metrics correctly', () {
      SyncFlowDebugger.start('test-user-123');
      
      // Simulate processing 3 emails
      for (int i = 1; i <= 3; i++) {
        SyncFlowDebugger.logStep('EMAIL_PROCESSED', 'Email $i');
        SyncFlowDebugger.logStep('PDF_UNLOCKED', 'PDF $i');
        SyncFlowDebugger.logStep('DB_STORED', 'Statement $i');
        SyncFlowDebugger.logStep('TRANSACTION_STORED', 'Transactions', data: {'count': 50});
      }
      
      final report = SyncFlowDebugger.generateReport();
      
      expect(report, contains('Emails Processed: 3'));
      expect(report, contains('Statements Stored: 3'));
      expect(report, contains('PDFs Unlocked: 3'));
    });
  });
}

// Test class using the mixin
class TestServiceWithMixin with SyncFlowDebugging {
  void performOperation() {
    debugStep('OPERATION_START', 'Starting operation');
    
    // Simulate some work
    final timer = debugStartTimer('Internal Operation');
    
    // Do work...
    
    debugEndTimer('Internal Operation', timer);
    
    debugStep('OPERATION_END', 'Operation completed');
  }
}
