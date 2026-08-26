import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

class LocalStorageService {
  static Future<List<Map<String, dynamic>>> scanForPdfs() async {
    final List<Map<String, dynamic>> allPdfs = [];
    final directories = await _getSearchDirectories();
    for (var dir in directories) {
      if (!await dir.exists()) continue;
      final pdfs = await _scanDirectoryForPdfs(dir);
      allPdfs.addAll(pdfs);
    }
    return allPdfs;
  }

  static Future<List<Directory>> _getSearchDirectories() async {
    final List<Directory> dirs = [];
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) dirs.add(downloads);
      final documents = await getApplicationDocumentsDirectory();
      dirs.add(documents);
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        if (external != null) dirs.add(external);
        dirs.add(Directory('/storage/emulated/0/Download'));
        dirs.add(Directory('/storage/emulated/0/Documents'));
        dirs.add(Directory('/storage/emulated/0/DCIM'));
      }
    } catch (e) {
      print('Error getting directories: $e');
    }
    return dirs;
  }

  static Future<List<Map<String, dynamic>>> _scanDirectoryForPdfs(Directory dir) async {
    final List<Map<String, dynamic>> pdfs = [];
    try {
      // Use recursive scan to find PDFs in subfolders
      final entities = await dir.list(recursive: true, followLinks: false).handleError((e) {
        print('Error listing ${dir.path}: $e');
      }).toList();
      
      for (var entity in entities) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.pdf') {
          try {
            final stat = await entity.stat();
            pdfs.add({
              'name': p.basename(entity.path),
              'path': entity.path,
              'size': stat.size,
            });
          } catch (e) {
            // Skip files that can't be accessed
          }
        }
      }
    } catch (e) {
      print('Error scanning ${dir.path}: $e');
    }
    return pdfs;
  }
}