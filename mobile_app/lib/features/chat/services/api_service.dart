import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef JsonMap = Map<String, dynamic>;

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? _defaultBaseUrl;

  final http.Client _client;
  final String baseUrl;

  static String get _defaultBaseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }

    if (kIsWeb) {
      return 'http://localhost:5000';
    }

    // Android emulator -> host machine localhost
    return 'http://10.0.2.2:5000';
  }

  Future<JsonMap> chat({
    required String message,
    required JsonMap userContext,
  }) async {
    final uri = Uri.parse('$baseUrl/chat');

    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': message, 'user_context': userContext}),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Chat request failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response format');
    }
    return decoded;
  }

  /// Gemini-backed personalized home content (requires backend `GEMINI_API_KEY`).
  Future<JsonMap> personalizedHome(JsonMap body) async {
    final uri = Uri.parse('$baseUrl/personalized_home');

    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Personalized home failed: ${resp.statusCode} ${resp.body}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response format');
    }
    return decoded;
  }
}
