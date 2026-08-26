import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RecentStorageService {
  static const String _key = 'recent_documents';

  static Future<void> saveRecentDocument(Map<String, dynamic> doc) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? existing = prefs.getStringList(_key);
    List<Map<String, dynamic>> recent = existing?.map((e) => jsonDecode(e) as Map<String, dynamic>).toList() ?? [];
    recent.removeWhere((item) => item['path'] == doc['path']);
    recent.insert(0, {
      'name': doc['name'],
      'path': doc['path'],
      'size': doc['size'] ?? 0,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (recent.length > 50) recent = recent.sublist(0, 50);
    final jsonList = recent.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_key, jsonList);
  }

  static Future<List<Map<String, dynamic>>> getRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? data = prefs.getStringList(_key);
    if (data == null) return [];
    return data.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> clearRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}