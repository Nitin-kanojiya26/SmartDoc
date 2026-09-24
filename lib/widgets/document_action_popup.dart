import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartdoc/services/tts_service.dart';
import 'package:smartdoc/services/gemini_service.dart';
import 'package:smartdoc/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DocumentActionPopup extends StatefulWidget {
  final String fileName;
  final String extractedText;
  final String? selectedText;
  final VoidCallback? onClose;

  const DocumentActionPopup({
    super.key,
    required this.fileName,
    required this.extractedText,
    this.selectedText,
    this.onClose,
  });

  @override
  State<DocumentActionPopup> createState() => _DocumentActionPopupState();
}

class _DocumentActionPopupState extends State<DocumentActionPopup>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // TTS State
  bool _isSpeaking = false;
  double _speed = 0.5;
  double _pitch = 1.0;
  Map<String, String>? _selectedVoice;

  // Summary State
  String _summary = '';
  bool _loadingSummary = false;
  bool _isSummarySpeaking = false;
  bool _detailedSummary = false;

  // Selected Text for TTS
  String _selectedTextForTts = '';

  // Q&A State
  final TextEditingController _questionController = TextEditingController();
  List<Map<String, String>> _chatHistory = [];
  bool _loadingAnswer = false;

  // AI Limits
  int _estimatedTotalPages = 1;
  RangeValues _pageRange = const RangeValues(1, 1);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    
    _estimatedTotalPages = (widget.extractedText.length / 2500).ceil().clamp(1, 9999);
    _pageRange = RangeValues(1, _estimatedTotalPages > 10 ? 10 : _estimatedTotalPages.toDouble());

    _speed = TtsService.getRate();
    _pitch = TtsService.getPitch();

    TtsService.initTts().then((_) {
      if (mounted) {
        setState(() {
          _selectedVoice = TtsService.selectedVoice;
        });
      }
    });

    _loadCachedData();
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Summary
    final summaryCached = prefs.getString('summary_${widget.fileName}');
    final summaryTimestamp = prefs.getInt('summary_time_${widget.fileName}');
    
    if (summaryCached != null && summaryTimestamp != null) {
      final savedTime = DateTime.fromMillisecondsSinceEpoch(summaryTimestamp);
      if (DateTime.now().difference(savedTime).inHours < 12) {
        if (mounted) {
          setState(() {
            _summary = summaryCached;
          });
        }
      } else {
        await prefs.remove('summary_${widget.fileName}');
        await prefs.remove('summary_time_${widget.fileName}');
      }
    }

    // Load Chat
    final chatHistoryJson = prefs.getString('chat_history_${widget.fileName}');
    final chatTimestamp = prefs.getInt('chat_time_${widget.fileName}');

    if (chatHistoryJson != null && chatTimestamp != null) {
      final savedTime = DateTime.fromMillisecondsSinceEpoch(chatTimestamp);
      if (DateTime.now().difference(savedTime).inHours < 12) {
        if (mounted) {
          setState(() {
            try {
              final List<dynamic> decoded = jsonDecode(chatHistoryJson);
              _chatHistory = decoded.map((e) => Map<String, String>.from(e)).toList();
            } catch (e) {
              _chatHistory = [];
            }
          });
        }
      } else {
        await prefs.remove('chat_history_${widget.fileName}');
        await prefs.remove('chat_time_${widget.fileName}');
      }
    }
  }

  Future<void> _saveCachedSummary(String summaryText) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('summary_${widget.fileName}', summaryText);
    await prefs.setInt('summary_time_${widget.fileName}', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _questionController.dispose();
    TtsService.stop();
    super.dispose();
  }

  void _speak() async {
    final textToSpeak = (widget.selectedText != null && widget.selectedText!.isNotEmpty)
        ? widget.selectedText!
        : widget.extractedText;
    if (textToSpeak.isEmpty) return;
    setState(() => _isSpeaking = true);
    await TtsService.speak(textToSpeak, rate: _speed, pitch: _pitch);
    if (mounted) {
      setState(() => _isSpeaking = false);
    }
  }

  void _pause() async {
    await TtsService.pause();
    setState(() {
      _isSpeaking = false;
      _isSummarySpeaking = false;
    });
  }

  void _stop() async {
    await TtsService.stop();
    setState(() {
      _isSpeaking = false;
      _isSummarySpeaking = false;
    });
  }

  void _speakSummary() async {
    if (_summary.isEmpty) return;
    setState(() => _isSummarySpeaking = true);
    await TtsService.speak(_summary, rate: _speed, pitch: _pitch);
    if (mounted) {
      setState(() => _isSummarySpeaking = false);
    }
  }

  String _getTextToProcess() {
    int startChar = (_pageRange.start.toInt() - 1) * 2500;
    int endChar = _pageRange.end.toInt() * 2500;
    
    if (startChar < 0) startChar = 0;
    if (endChar > widget.extractedText.length) endChar = widget.extractedText.length;
    
    if (startChar >= widget.extractedText.length) return '';
    
    return widget.extractedText.substring(startChar, endChar) + 
           ((endChar < widget.extractedText.length) ? '\n\n[...TEXT TRUNCATED DUE TO PAGE LIMIT...]' : '');
  }

  Future<void> _generateSummary() async {
    setState(() => _loadingSummary = true);
    final text = _getTextToProcess();
    final result = await GeminiService.summarizeText(text);
    if (mounted) {
      setState(() {
        _summary = result;
        _loadingSummary = false;
      });
      _saveCachedSummary(result);
    }
  }

  Future<void> _downloadSummary() async {
    if (_summary.isEmpty) return;
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            final String cleanedSummary = _summary
                .replaceAll('–', '-')
                .replaceAll('—', '-')
                .replaceAll('’', "'")
                .replaceAll('‘', "'")
                .replaceAll('“', '"')
                .replaceAll('”', '"')
                .replaceAll('•', '*')
                .replaceAll('…', '...')
                .replaceAll(RegExp(r'[^\x00-\x7F]'), '');
                
            final String cleanedFileName = widget.fileName
                .replaceAll(RegExp(r'[^\x00-\x7F]'), '');
                
            final List<pw.Widget> content = [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Summary of $cleanedFileName',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
            ];

            final paragraphs = cleanedSummary.split(RegExp(r'\n+'));
            for (var p in paragraphs) {
              if (p.trim().isEmpty) continue;
              content.add(
                pw.Paragraph(
                  text: p.trim(),
                  style: const pw.TextStyle(
                    fontSize: 12,
                    lineSpacing: 1.5,
                  ),
                ),
              );
            }

            return content;
          },
        ),
      );

      final pdfBytes = await pdf.save();
      
      final docsDir = await getApplicationDocumentsDirectory();
      final directory = Directory('${docsDir.path}/Summary');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final safeName = widget.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'summary_$safeName.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      
      // Automatically add it to the database under the 'Summary' category so it appears immediately!
      await DatabaseService().upsertDocument({
        'name': fileName,
        'path': file.path,
        'size': pdfBytes.length,
        'category': 'Summary',
        'is_override': 1, // Lock it to Summary category
        'text_content': _summary, // Also save the summary as its text content
        'last_opened': DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Summary saved to your Categories!'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 140,
              left: 20,
              right: 20,
            ),
            dismissDirection: DismissDirection.up,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 140,
              left: 20,
              right: 20,
            ),
            dismissDirection: DismissDirection.up,
          ),
        );
      }
    }
  }

  Future<void> _saveCachedChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_history_${widget.fileName}', jsonEncode(_chatHistory));
    await prefs.setInt('chat_time_${widget.fileName}', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    
    setState(() {
      _chatHistory.add({'role': 'user', 'text': question});
      _questionController.clear();
      _loadingAnswer = true;
    });
    
    final text = _getTextToProcess();
    final res = await GeminiService.askQuestion(text, question);
    
    if (mounted) {
      setState(() {
        _chatHistory.add({'role': 'ai', 'text': res});
        _loadingAnswer = false;
      });
      _saveCachedChat();
    }
  }

  void _showFullScreenSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Text(
                  _summary,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_isSummarySpeaking) {
                        _pause();
                        setModalState(() {});
                      } else {
                        if (_summary.isEmpty) return;
                        setModalState(() => _isSummarySpeaking = true);
                        setState(() => _isSummarySpeaking = true);
                        await TtsService.speak(_summary, rate: _speed, pitch: _pitch);
                        if (mounted) {
                          setModalState(() => _isSummarySpeaking = false);
                          setState(() => _isSummarySpeaking = false);
                        }
                      }
                    },
                    icon: Icon(_isSummarySpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
                    label: Text(_isSummarySpeaking ? 'Pause' : 'Listen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showApiKeyDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentKey = prefs.getString('gemini_api_key') ?? '';
    final controller = TextEditingController(text: currentKey);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gemini API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To avoid free quota exhaustion, please use your own Gemini API key.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                // Ideally launch URL: https://aistudio.google.com/app/apikey
              },
              child: const Text(
                'Get a free key here:\nhttps://aistudio.google.com/app/apikey',
                style: TextStyle(fontSize: 13, color: Colors.blue, decoration: TextDecoration.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
                hintText: 'AIza...',
              ),
              obscureText: true,
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
              await prefs.setString('gemini_api_key', controller.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getFriendlyLanguageName(String? locale) {
    if (locale == null) return 'Default';
    final l = locale.toLowerCase();
    if (l.startsWith('en-us')) return 'English (US)';
    if (l.startsWith('en-gb')) return 'English (UK)';
    if (l.startsWith('en-au')) return 'English (Australia)';
    if (l.startsWith('en-in')) return 'English (India)';
    if (l.startsWith('fr-fr')) return 'French (France)';
    if (l.startsWith('es-es')) return 'Spanish (Spain)';
    if (l.startsWith('es-us')) return 'Spanish (US)';
    if (l.startsWith('de-de')) return 'German (Germany)';
    if (l.startsWith('it-it')) return 'Italian (Italy)';
    if (l.startsWith('ja-jp')) return 'Japanese (Japan)';
    if (l.startsWith('ko-kr')) return 'Korean (Korea)';
    if (l.startsWith('hi-in')) return 'Hindi (India)';
    return locale.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 30,
                spreadRadius: 0,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.fileName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: -0.3,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: _showApiKeyDialog,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.vpn_key_rounded, size: 18, color: theme.textTheme.bodyMedium?.color),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (widget.onClose != null) widget.onClose!();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 18, color: theme.textTheme.bodyMedium?.color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  labelColor: theme.colorScheme.onPrimary,
                  unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Audio'),
                    Tab(text: 'Summary'),
                    Tab(text: 'Ask AI'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildReadAloudTab(scrollController),
                    _buildSummarizeTab(scrollController),
                    _buildAskTab(scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReadAloudTab(ScrollController scrollController) {
    final theme = Theme.of(context);
    final hasSelectedText = widget.selectedText != null && widget.selectedText!.isNotEmpty;
    
    return SingleChildScrollView(
      controller: _tabController.index == 0 ? scrollController : null,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (hasSelectedText)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Reading selected text only',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIconButton(
                icon: Icons.play_arrow_rounded,
                active: !_isSpeaking,
                onTap: _speak,
              ),
              const SizedBox(width: 16),
              _buildIconButton(
                icon: Icons.pause_rounded,
                active: _isSpeaking,
                onTap: _pause,
              ),
              const SizedBox(width: 16),
              _buildIconButton(
                icon: Icons.stop_rounded,
                active: _isSpeaking || TtsService.state == TtsState.paused,
                onTap: _stop,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _buildSliderRow(
            label: 'Speed',
            value: _speed,
            min: 0.1,
            max: 1.0,
            onChanged: (v) async {
              setState(() => _speed = v);
              await TtsService.setRate(v);
            },
          ),
          const SizedBox(height: 12),
          _buildSliderRow(
            label: 'Pitch',
            value: _pitch,
            min: 0.5,
            max: 2.0,
            onChanged: (v) async {
              setState(() => _pitch = v);
              await TtsService.setPitch(v);
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, String>>(
                value: _selectedVoice,
                items: TtsService.voices.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final voice = entry.value;
                  final friendlyName = _getFriendlyLanguageName(voice['locale']);
                  return DropdownMenuItem(
                    value: voice,
                    child: Text(
                      '$friendlyName - Voice $index',
                      style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color),
                    ),
                  );
                }).toList(),
                onChanged: (voice) async {
                  if (voice != null) {
                    setState(() => _selectedVoice = voice);
                    await TtsService.setVoice(voice);
                  }
                },
                isExpanded: true,
                hint: Text('Voice Engine', style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color)),
                dropdownColor: theme.colorScheme.surface,
                iconEnabledColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiLimitControls() {
    if (_estimatedTotalPages <= 3) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Large document detected (~$_estimatedTotalPages pages). Max 10 pages allowed at once.\nPlease select the start and end pages to process.',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Page Range (Max 10):', style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color)),
            Text('${_pageRange.start.toInt()} - ${_pageRange.end.toInt()} / $_estimatedTotalPages', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
          ],
        ),
        RangeSlider(
          values: _pageRange,
          min: 1,
          max: _estimatedTotalPages.toDouble(),
          divisions: _estimatedTotalPages > 1 ? _estimatedTotalPages - 1 : 1,
          onChanged: (val) {
            RangeValues newRange = val;
            if (newRange.end - newRange.start > 9) {
              bool justHitLimit = (_pageRange.end - _pageRange.start <= 9);
              if (newRange.start != _pageRange.start) {
                newRange = RangeValues(newRange.start, newRange.start + 9);
              } else {
                newRange = RangeValues(newRange.end - 9, newRange.end);
              }
              if (justHitLimit) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Maximum 10 pages allowed at once. Range adjusted.'), duration: Duration(seconds: 2)),
                );
              }
            }
            setState(() {
              _pageRange = newRange;
              if (_summary.isNotEmpty) _summary = '';
            });
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSummarizeTab(ScrollController scrollController) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      controller: _tabController.index == 1 ? scrollController : null,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAiLimitControls(),
          Row(
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: _detailedSummary,
                  activeColor: theme.colorScheme.primary,
                  checkColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _detailedSummary = val ?? false;
                      if (_summary.isNotEmpty) {
                        _summary = '';
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Comprehensive breakdown',
                style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _summary.isEmpty && !_loadingSummary
              ? Center(
            child: OutlinedButton.icon(
              onPressed: _generateSummary,
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Generate Summary'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.textTheme.bodyLarge?.color,
                side: BorderSide(color: theme.colorScheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          )
              : _loadingSummary
              ? Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          )
              : Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.textTheme.bodyMedium?.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'KEY TAKEAWAYS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.open_in_full_rounded, size: 16, color: theme.textTheme.bodyMedium?.color),
                          onPressed: _showFullScreenSummary,
                        ),
                        IconButton(
                          icon: Icon(Icons.ios_share_rounded, size: 16, color: theme.textTheme.bodyMedium?.color),
                          onPressed: _downloadSummary,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSummarySpeaking ? _pause : _speakSummary,
                      icon: Icon(
                        _isSummarySpeaking ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 16,
                      ),
                      label: Text(_isSummarySpeaking ? 'Pause' : 'Listen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String role, String text) {
    final isUser = role == 'user';
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: !isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isUser ? null : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: isUser ? theme.colorScheme.onPrimary : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: const Radius.circular(4),
          ),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildAskTab(ScrollController scrollController) {
    final theme = Theme.of(context);
    final bool showLimits = _estimatedTotalPages > 3;
    final int extraItems = showLimits ? 1 : 0;
    
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _tabController.index == 2 ? scrollController : null,
            padding: const EdgeInsets.all(24),
            itemCount: _chatHistory.length + (_loadingAnswer ? 1 : 0) + extraItems,
            itemBuilder: (context, index) {
              if (showLimits && index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildAiLimitControls(),
                );
              }
              
              final msgIndex = index - extraItems;
              if (msgIndex == _chatHistory.length) return _buildLoadingBubble();
              
              final msg = _chatHistory[msgIndex];
              return _buildChatBubble(msg['role']!, msg['text']!);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                ? 16 
                : 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant ?? Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    style: const TextStyle(fontSize: 14),
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(fontSize: 14, color: theme.textTheme.bodySmall?.color),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(bottom: 4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _loadingAnswer ? null : _askQuestion,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: _questionController.text.trim().isNotEmpty ? Colors.blue : theme.colorScheme.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded, 
                      size: 16, 
                      color: _questionController.text.trim().isNotEmpty ? Colors.white : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? theme.colorScheme.onPrimary : theme.textTheme.bodyMedium?.color,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.outlineVariant,
              thumbColor: theme.colorScheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}