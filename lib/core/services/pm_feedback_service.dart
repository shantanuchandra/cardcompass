import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Service to handle Product Manager feedback and persist it both locally
/// and directly inside the project workspace directory for AI agents to refer to.
class PmFeedbackService {
  static final PmFeedbackService _instance = PmFeedbackService._internal();
  factory PmFeedbackService() => _instance;
  PmFeedbackService._internal();

  static const String _boxName = 'pm_feedback_logs';
  static const String _projectRoot = '/Users/shantanuchandra/Downloads/Personal/cardcompass';

  /// Save new feedback to local storage and synchronize it to the project workspace
  Future<void> saveFeedback(String feedbackText) async {
    try {
      if (feedbackText.trim().isEmpty) return;

      final box = await Hive.openBox(_boxName);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final entry = {
        'id': id,
        'timestamp': DateTime.now().toIso8601String(),
        'feedback': feedbackText.trim(),
      };
      
      await box.put(id, entry);
      print('💾 Saved PM feedback entry locally: $id');

      // Attempt to sync write directly to the project root directory
      await syncToProjectRoot();
    } catch (e) {
      print('❌ Failed to save PM feedback: $e');
    }
  }

  /// Get all past feedback entries sorted by newest first
  Future<List<Map<String, dynamic>>> getFeedbacks() async {
    try {
      final box = await Hive.openBox(_boxName);
      final list = box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      list.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
      return list;
    } catch (e) {
      print('❌ Failed to retrieve PM feedback entries: $e');
      return [];
    }
  }

  /// Delete a feedback entry
  Future<void> deleteFeedback(String id) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.delete(id);
      await syncToProjectRoot();
    } catch (e) {
      print('❌ Failed to delete feedback entry: $e');
    }
  }

  /// Write the entire feedback registry to the project root directory
  Future<void> syncToProjectRoot() async {
    if (kIsWeb) {
      print('ℹ️ Running on Web. Direct workspace filesystem syncing is disabled.');
      return;
    }
    
    try {
      final feedbacks = await getFeedbacks();
      final file = File('$_projectRoot/pm_pruning_feedback.json');
      
      // Format as readable indented JSON
      final encoder = const JsonEncoder.withIndent('  ');
      final jsonContent = encoder.convert(feedbacks);
      
      await file.writeAsString(jsonContent);
      print('💾 Workspace feedback file updated at: ${file.path}');
    } catch (e) {
      print('⚠️ Failed to sync write to workspace root: $e');
    }
  }
}
