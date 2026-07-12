import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/ai_config.dart';

/// Sends Gemini requests through the authenticated backend on web so provider
/// credentials are never compiled into the public JavaScript bundle.
Future<http.Response> sendGeminiRequest(Map<String, dynamic> payload) async {
  if (kIsWeb) {
    final response = await Supabase.instance.client.functions.invoke(
      'gemini-proxy',
      body: {'model': AIConfig.geminiModel, 'payload': payload},
    );
    return http.Response(
      response.data is String
          ? response.data as String
          : jsonEncode(response.data),
      response.status,
    );
  }

  final response = await http.post(
    Uri.parse(AIConfig.geminiGenerateUrl),
    headers: AIConfig.geminiHeaders,
    body: jsonEncode(payload),
  );
  return response;
}
