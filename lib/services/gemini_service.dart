import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeminiService {
  static const String modelName = 'gemini-2.5-flash';

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final customKey = prefs.getString('gemini_api_key') ?? '';
    if (customKey.isNotEmpty) return customKey;
    return dotenv.env['GEMINI_API_KEY'] ?? '';
  }

  static Future<Uri> _getApiUri() async {
    final key = await getApiKey();
    return Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$key',
    );
  }

  static Future<String> summarizeText(String documentText) async {
    final key = await getApiKey();
    if (key.isEmpty || key.startsWith('YOUR_')) {
      return '⚠️ Please provide your free Gemini API key.\n\nTo get a free key:\n1. Go to https://aistudio.google.com/app/apikey\n2. Create an API key\n3. Add it to the app settings or .env file.';
    }
    if (!key.startsWith('AIza')) {
      return '⚠️ Invalid API Key format. Gemini API keys start with "AIza".';
    }
    if (documentText.trim().isEmpty) {
      return 'No document text found to summarize.';
    }

    try {
      final prompt =
          'Provide a highly professional and structured summary of the following document. Use clear headings, bullet points for key takeaways, and ensure a formal tone. Extract the core essence, major themes, and actionable insights if any:\n\n$documentText';
      return await _sendRequest(prompt);
    } catch (e) {
      return 'Error generating summary: $e';
    }
  }

  static Future<String> askQuestion(String documentText, String question) async {
    final key = await getApiKey();
    if (key.isEmpty || key.startsWith('YOUR_')) {
      return '⚠️ Please provide your free Gemini API key.\n\nTo get a free key:\n1. Go to https://aistudio.google.com/app/apikey\n2. Create an API key\n3. Add it to the app settings or .env file.';
    }
    if (question.trim().isEmpty) {
      return 'Please enter a valid question.';
    }

    try {
      final prompt =
          'Based on the following document, answer the question in a professional manner.\nIf the question is outside the scope of the document, explicitly and politely state that it is outside the scope of the provided document, but then provide a helpful answer or idea based on your general knowledge anyway.\n\nDocument:\n$documentText\n\nQuestion: $question';
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

    final uri = await _getApiUri();
    final response = await http.post(
      uri,
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