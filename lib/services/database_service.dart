import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = await getDatabasesPath();
    final dbPath = join(path, 'smartdoc_v2.db'); // Changed DB name for fresh start
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Documents table
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT UNIQUE NOT NULL,
        size INTEGER NOT NULL,
        category TEXT NOT NULL,
        is_override INTEGER DEFAULT 0,
        text_content TEXT,
        tags TEXT,
        last_opened INTEGER
      )
    ''');
    
    // Custom Categories table
    await db.execute('''
      CREATE TABLE custom_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        keywords TEXT
      )
    ''');

    // Indices for faster search and filtering
    await db.execute('CREATE INDEX idx_category ON documents(category)');
    await db.execute('CREATE INDEX idx_content ON documents(text_content)');
    await db.execute('CREATE INDEX idx_name ON documents(file_name)');
  }

  // --- Document Operations ---

  /// Insert or update a document in the database.
  Future<void> upsertDocument(Map<String, dynamic> doc) async {
    final db = await database;
    await db.insert(
      'documents',
      {
        'file_name': doc['name'],
        'file_path': doc['path'],
        'size': doc['size'],
        'category': doc['category'] ?? 'General',
        'is_override': doc['is_override'] ?? 0,
        'text_content': doc['text_content'],
        'tags': doc['tags'],
        'last_opened': doc['last_opened'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batch update or insert many documents (useful for background sync).
  Future<void> syncDocuments(List<Map<String, dynamic>> docs) async {
    final db = await database;
    final batch = db.batch();
    for (var doc in docs) {
      batch.insert(
        'documents',
        {
          'file_name': doc['name'],
          'file_path': doc['path'],
          'size': doc['size'],
          'category': doc['category'],
          'is_override': doc['is_override'] ?? 0,
          'text_content': doc['text_content'],
          'tags': doc['tags'],
          'last_opened': doc['last_opened'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // Ignore if exists to preserve overrides
      );
    }
    await batch.commit(noResult: true);
  }

  /// Check if a document path exists in the database.
  Future<bool> documentExists(String path) async {
    final db = await database;
    final result = await db.query(
      'documents',
      columns: ['id'],
      where: 'file_path = ?',
      whereArgs: [path],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get all documents, returning them in a categorized format.
  Future<Map<String, List<Map<String, dynamic>>>> getAllDocumentsCategorized() async {
    final db = await database;
    final results = await db.query('documents');
    
    final Map<String, List<Map<String, dynamic>>> categorized = {};
    
    // Add custom categories first so they appear even if empty
    final customCats = await getCustomCategories();
    for (var cat in customCats) {
      categorized[cat['name'] as String] = [];
    }

    for (var row in results) {
      final category = row['category'] as String;
      final doc = {
        'id': row['id'],
        'name': row['file_name'],
        'path': row['file_path'],
        'size': row['size'],
        'category': category,
        'is_override': (row['is_override'] as int) == 1,
        'text_content': row['text_content'],
        'tags': row['tags'],
        'last_opened': row['last_opened'],
      };
      categorized.putIfAbsent(category, () => []).add(doc);
    }
    return categorized;
  }
  
  /// Get all documents as a flat list.
  Future<List<Map<String, dynamic>>> getAllDocuments() async {
    final db = await database;
    final results = await db.query('documents', orderBy: 'last_opened DESC');
    return results.map((row) => {
        'id': row['id'],
        'name': row['file_name'],
        'path': row['file_path'],
        'size': row['size'],
        'category': row['category'],
        'is_override': (row['is_override'] as int) == 1,
        'text_content': row['text_content'],
        'tags': row['tags'],
        'last_opened': row['last_opened'],
    }).toList();
  }

  /// Update just the category (manual override)
  Future<void> updateCategory(String filePath, String category) async {
    final db = await database;
    await db.update(
      'documents',
      {'category': category, 'is_override': 1},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  /// Search documents
  Future<List<Map<String, dynamic>>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await database;
    final results = await db.rawQuery('''
      SELECT * FROM documents
      WHERE file_name LIKE ? OR text_content LIKE ?
      ORDER BY last_opened DESC
    ''', ['%$query%', '%$query%']);
    
    return results.map((row) => {
        'id': row['id'],
        'name': row['file_name'],
        'path': row['file_path'],
        'size': row['size'],
        'category': row['category'],
    }).toList();
  }
  
  /// Update last opened timestamp
  Future<void> updateLastOpened(String filePath) async {
    final db = await database;
    await db.update(
      'documents',
      {'last_opened': DateTime.now().millisecondsSinceEpoch},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  /// Delete documents that no longer exist on disk
  Future<void> removeDeletedFiles(List<String> validPaths) async {
    if (validPaths.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(validPaths.length, '?').join(',');
    await db.delete(
      'documents',
      where: 'file_path NOT IN ($placeholders)',
      whereArgs: validPaths,
    );
  }

  /// Clear all documents (optional).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('documents');
  }

  // --- Custom Categories Operations ---

  /// Get all custom categories
  Future<List<Map<String, dynamic>>> getCustomCategories() async {
    final db = await database;
    return await db.query('custom_categories');
  }

  /// Add a custom category
  Future<void> addCustomCategory(String name, String keywords) async {
    final db = await database;
    await db.insert(
      'custom_categories',
      {'name': name, 'keywords': keywords},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a custom category
  Future<void> deleteCustomCategory(String name) async {
    final db = await database;
    await db.delete(
      'custom_categories',
      where: 'name = ?',
      whereArgs: [name],
    );
    // Move documents in this category back to General
    await db.update(
      'documents',
      {'category': 'General', 'is_override': 0},
      where: 'category = ? AND is_override = 1',
      whereArgs: [name],
    );
  }
  
  /// Get custom categories map for CategoryService
  Future<Map<String, List<String>>> getCustomCategoryKeywords() async {
    final customCats = await getCustomCategories();
    final Map<String, List<String>> map = {};
    for (var cat in customCats) {
      final keywordsStr = cat['keywords'] as String? ?? '';
      final keywords = keywordsStr
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
      if (keywords.isNotEmpty) {
         map[cat['name'] as String] = keywords;
      }
    }
    return map;
  }
}
