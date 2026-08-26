import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  // 🔑 Get actual Gemini API key from .env file
  static String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static const String modelName = 'gemini-2.5-flash';

  static Uri _getApiUri() {
    return Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );
  }

  static Future<String> summarizeText(String documentText) async {
    if (apiKey.isEmpty || apiKey.startsWith('YOUR_')) {
      return '⚠️ Please set a valid Gemini API key in gemini_service.dart.';
    }
    if (!apiKey.startsWith('AIza')) {
      return '⚠️ Invalid API Key format. Gemini API keys start with "AIza".';
    }
    if (documentText.trim().isEmpty) {
      return 'No document text found to summarize.';
    }

    try {
      final prompt =
          'Provide a comprehensive and detailed summary of the following document. Include all key information, major themes, and important takeaways:\n\n$documentText';
      return await _sendRequest(prompt);
    } catch (e) {
      return 'Error generating summary: $e';
    }
  }

  static Future<String> askQuestion(String documentText, String question) async {
    if (apiKey.isEmpty || apiKey.startsWith('YOUR_')) {
      return '⚠️ Please set a valid Gemini API key in gemini_service.dart.';
    }
    if (question.trim().isEmpty) {
      return 'Please enter a valid question.';
    }

    try {
      final prompt =
          'Based on the following document, answer the question.\nIf the question is outside the scope of the document, explicitly and politely state that it is outside the scope of the provided document, but then provide a helpful answer or idea based on your general knowledge anyway.\n\nDocument:\n$documentText\n\nQuestion: $question';
      return await _sendRequest(prompt);
    } catch (e) {
      return 'Error answering question: $e';
    }
  }

  static Future<String> _sendRequest(String prompt) async {
    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    };

    final response = await http.post(
      _getApiUri(),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates[0]['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? 'No text generated.';
        }
      }
      return 'No response generated from Gemini.';
    } else {
      final errorData = jsonDecode(response.body);
      final message = errorData['error']?['message'] ?? response.reasonPhrase;
      throw Exception('Gemini API Error (${response.statusCode}): $message');
    }
  }
}