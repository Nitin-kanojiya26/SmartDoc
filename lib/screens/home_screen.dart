import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'package:smartdoc/services/auth_service.dart';
import 'package:smartdoc/services/pdf_service.dart';
import 'package:smartdoc/services/tts_service.dart';
import 'package:smartdoc/services/local_storage_service.dart';
import 'package:smartdoc/services/recent_storage_service.dart';
import 'package:smartdoc/services/database_service.dart';
import 'package:smartdoc/services/reading_progress_service.dart';
import 'package:smartdoc/screens/pdf_viewer_screen.dart';
import 'package:smartdoc/services/category_service.dart';
import 'package:smartdoc/theme/theme_service.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Recent documents (from shared_preferences)
  List<Map<String, dynamic>> _recentDocs = [];
  bool _loadingRecent = true;

  // Categorized documents
  Map<String, List<Map<String, dynamic>>> _categoryGroups = {};
  bool _loadingCategories = true;
  bool _permissionDenied = false;

  // 🔍 Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    TtsService.initTts();
    _initializeApp();

    _searchController.addListener(() {
      final query = _searchController.text.trim();
      setState(() {
        _searchQuery = query;
        if (query.isNotEmpty) {
          _isSearching = true;
          _performSearch(query);
        } else {
          _isSearching = false;
          _searchResults = [];
        }
      });
    });
  }

  Future<void> _initializeApp() async {
    await _requestInitialPermissions();
    _refreshAll();
  }

  Future<void> _requestInitialPermissions() async {
    if (kIsWeb) return;
    
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        await [Permission.manageExternalStorage].request();
      } else {
        await [Permission.storage].request();
      }
    } else {
      await [Permission.storage].request();
    }
  }

  Future<void> _performSearch(String query) async {
    final results = await DatabaseService().search(query);
    setState(() {
      _searchResults = results;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    _loadRecentFromLocal();
    await _loadFromDatabase();
    _syncDocumentsInBackground();
  }

  Future<void> _loadFromDatabase() async {
    setState(() => _loadingCategories = true);
    try {
      final categorized = await DatabaseService().getAllDocumentsCategorized();
      if (mounted) {
        setState(() {
          _categoryGroups = categorized;
          _loadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadRecentFromLocal() async {
    setState(() => _loadingRecent = true);
    try {
      final docs = await RecentStorageService.getRecentDocuments();
      if (mounted) {
        setState(() {
          _recentDocs = docs;
          _loadingRecent = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _syncDocumentsInBackground() async {
    if (kIsWeb) return;
    try {
      bool canAccess = false;
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 30) {
          var status = await Permission.manageExternalStorage.status;
          canAccess = status.isGranted;
        } else {
          var status = await Permission.storage.status;
          canAccess = status.isGranted;
        }
      } else {
        var status = await Permission.storage.status;
        canAccess = status.isGranted;
      }

      if (!canAccess) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }

      final scannedPdfs = await LocalStorageService.scanForPdfs();
      if (scannedPdfs.isEmpty) return;

      final dbService = DatabaseService();
      final customCats = await dbService.getCustomCategoryKeywords();
      List<Map<String, dynamic>> newDocs = [];
      List<String> validPaths = [];

      for (var pdf in scannedPdfs) {
        final path = pdf['path'];
        validPaths.add(path);
        final exists = await dbService.documentExists(path);
        if (!exists) {
          final category = CategoryService.getBestCategory(pdf['name'], customCategories: customCats);
          pdf['category'] = category;
          newDocs.add(pdf);
        }
      }

      if (newDocs.isNotEmpty) {
        await dbService.syncDocuments(newDocs);
      }
      
      await dbService.removeDeletedFiles(validPaths);
      
      // Reload UI if there were changes
      if (newDocs.isNotEmpty || validPaths.length != _categoryGroups.values.fold(0, (sum, list) => sum + list.length)) {
        _loadFromDatabase();
      }
    } catch (e) {
      print('Background sync error: $e');
    }
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    try {
      Uint8List bytes = Uint8List(0);
      String text = '';
      String name = doc['name'] ?? 'Untitled';
      String path = doc['path'] ?? '';

      if (!kIsWeb && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
          text = await PdfService.extractTextFromBytes(bytes);

          // Update document in database with text content
          doc['text_content'] = text;
          await DatabaseService().upsertDocument(doc);
          await DatabaseService().updateLastOpened(path);

          // Re-categorize with full text if not overridden
          if (doc['is_override'] != true) {
            final customCats = await DatabaseService().getCustomCategoryKeywords();
            final newCategory = CategoryService.getBestCategory('$name $text', customCategories: customCats);
            if (newCategory != doc['category']) {
              await DatabaseService().updateCategory(path, newCategory);
              _loadFromDatabase();
            }
          }

          await RecentStorageService.saveRecentDocument(doc);
          _loadRecentFromLocal();
        } else {
          throw Exception('File does not exist.');
        }
      } else {
        text = "Sample text for web preview.";
        path = 'web_sample';
        // For web, we don't store in DB, but we can still open the viewer
      }

      if (mounted && (bytes.isNotEmpty || kIsWeb)) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              fileName: name,
              pdfBytes: bytes,
              extractedText: text,
              localPath: path,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showReCategorizeDialog(Map<String, dynamic> doc) async {
    final customCats = await DatabaseService().getCustomCategories();
    final List<String> categories = customCats.map((c) => c['name'] as String).toList();
    categories.addAll(CategoryService.categoryKeywords.keys);
    categories.add('General');
    
    final current = doc['category'] ?? 'General';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose new category',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ...categories.map((cat) => ListTile(
                leading: Radio<String>(
                  value: cat,
                  groupValue: current,
                  onChanged: (_) {
                    Navigator.pop(context);
                    _applyCategory(doc, cat);
                  },
                ),
                title: Text(cat),
              )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _applyCategory(Map<String, dynamic> doc, String newCategory) async {
    final path = doc['path'] ?? '';
    if (path.isEmpty) return;
    await DatabaseService().updateCategory(path, newCategory);
    _loadFromDatabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved to "$newCategory"'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final keywordsController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Category Name (e.g. University)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keywordsController,
                decoration: const InputDecoration(labelText: 'Keywords (comma separated)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final keywords = keywordsController.text.trim();
                if (name.isNotEmpty) {
                  await DatabaseService().addCustomCategory(name, keywords);
                  if (mounted) Navigator.pop(context);
                  await _loadFromDatabase();
                  _syncDocumentsInBackground(); // Recategorize based on new keywords
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category "$name" created!')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      }
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SmartDoc',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            fontSize: 22,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              themeService.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
            ),
            onPressed: () => themeService.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _refreshAll,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔍 Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search documents by name or content...',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          if (_isSearching)
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      'No documents found',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  return _buildDocCard(_searchResults[index]);
                },
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                labelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Recent'),
                  Tab(text: 'Categories'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRecentView(),
                  _buildCategoriesView(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentView() {
    if (_loadingRecent) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_recentDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No recent documents', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _recentDocs.length,
      itemBuilder: (context, index) {
        final doc = _recentDocs[index];
        return _buildDocCard(doc);
      },
    );
  }

  Widget _buildCategoriesView() {
    if (_loadingCategories && _categoryGroups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16),
            Text('Loading documents...', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }
    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Storage permission required', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () async {
                var status = await Permission.storage.status;
                if (status.isPermanentlyDenied) {
                  await openAppSettings();
                } else {
                  _syncDocumentsInBackground();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Grant Access'),
            ),
          ],
        ),
      );
    }
    if (_categoryGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No documents found', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _showAddCategoryDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Custom Category'),
            ),
          ],
        ),
      );
    }

    final categories = _categoryGroups.keys.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showAddCategoryDialog,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Category'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
        final category = categories[index];
        final docs = _categoryGroups[category]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Icon(_getCategoryIcon(category), size: 22),
            title: Text(category, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
            subtitle: Text(
              '${docs.length} document${docs.length > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
            onTap: () => _showCategoryDocs(category, docs),
          ),
        ),
        );
      },
    ),
    ),
    ],
    );
  }

  void _showCategoryDocs(String category, List<Map<String, dynamic>> initialDocs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setModalState) {
            final docs = _categoryGroups[category] ?? [];
            return Scaffold(
              appBar: AppBar(
                title: Text(category),
              ),
              body: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return _buildDocCard(doc);
                },
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );
                    if (result != null && result.files.single.path != null) {
                      final file = File(result.files.single.path!);
                      final stat = await file.stat();
                      final doc = {
                        'name': p.basename(file.path),
                        'path': file.path,
                        'size': stat.size,
                        'category': category,
                        'is_override': 1,
                      };
                      await DatabaseService().upsertDocument(doc);
                      await _loadFromDatabase();
                      setModalState(() {});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to $category')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add PDF'),
              ),
            );
          }
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Science':
        return Icons.science_outlined;
      case 'Programming':
        return Icons.code_rounded;
      case 'Business':
        return Icons.business_center_outlined;
      case 'History':
        return Icons.history_edu_rounded;
      case 'Mathematics':
        return Icons.calculate_outlined;
      case 'Literature':
        return Icons.menu_book_rounded;
      case 'Art & Design':
        return Icons.palette_outlined;
      case 'Health & Medicine':
        return Icons.health_and_safety_outlined;
      case 'Education':
        return Icons.school_outlined;
      case 'Social Sciences':
        return Icons.people_outline_rounded;
      case 'Engineering':
        return Icons.engineering_outlined;
      case 'Personal':
        return Icons.person_outline_rounded;
      default:
        return Icons.folder_outlined;
    }
  }

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final path = doc['path'] ?? '';

    return FutureBuilder<double>(
      future: path.isNotEmpty ? ReadingProgressService.getProgress(path) : Future.value(0.0),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? 0.0;
        return GestureDetector(
          onLongPress: () => _showReCategorizeDialog(doc),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Theme.of(context).cardTheme.color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 16),
                  ),
                  title: Text(
                    doc['name'] ?? 'Untitled',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
                  onTap: () => _openDocument(doc),
                ),
                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade300,
                            color: Colors.blue.shade700,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}