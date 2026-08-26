import 'package:shared_preferences/shared_preferences.dart';

class ReadingProgressService {
  static const String _prefixPage = 'page_';
  static const String _prefixTotal = 'total_';

  static Future<void> saveProgress(String localPath, int currentPage, int totalPages) async {
    if (localPath.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefixPage$localPath', currentPage);
    await prefs.setInt('$_prefixTotal$localPath', totalPages);
  }

  static Future<int> getCurrentPage(String localPath) async {
    if (localPath.isEmpty) return 1;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefixPage$localPath') ?? 1;
  }

  static Future<int> getTotalPages(String localPath) async {
    if (localPath.isEmpty) return 1;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefixTotal$localPath') ?? 1;
  }

  static Future<double> getProgress(String localPath) async {
    if (localPath.isEmpty) return 0.0;
    final current = await getCurrentPage(localPath);
    final total = await getTotalPages(localPath);
    if (total <= 0) return 0.0;
    return (current / total).clamp(0.0, 1.0);
  }

  static Future<void> clearProgress(String localPath) async {
    if (localPath.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefixPage$localPath');
    await prefs.remove('$_prefixTotal$localPath');
  }
}