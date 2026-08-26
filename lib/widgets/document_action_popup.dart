import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartdoc/services/tts_service.dart';
import 'package:smartdoc/services/gemini_service.dart';

class DocumentActionPopup extends StatefulWidget {
  final String fileName;
  final String extractedText;
  final VoidCallback? onClose;

  const DocumentActionPopup({
    super.key,
    required this.fileName,
    required this.extractedText,
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

  // Q&A State
  final TextEditingController _questionController = TextEditingController();
  String _answer = '';
  bool _loadingAnswer = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _speed = TtsService.getRate();
    _pitch = TtsService.getPitch();

    TtsService.initTts().then((_) {
      if (mounted) {
        setState(() {
          _selectedVoice = TtsService.selectedVoice;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _questionController.dispose();
    TtsService.stop();
    super.dispose();
  }

  void _speak() async {
    if (widget.extractedText.isEmpty) return;
    setState(() => _isSpeaking = true);
    await TtsService.speak(widget.extractedText, rate: _speed, pitch: _pitch);
  }

  void _pause() async {
    await TtsService.pause();
    setState(() => _isSpeaking = false);
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
  }

  Future<void> _generateSummary() async {
    setState(() => _loadingSummary = true);
    final result = await GeminiService.summarizeText(widget.extractedText);
    if (mounted) {
      setState(() {
        _summary = result;
        _loadingSummary = false;
      });
    }
  }

  Future<void> _downloadSummary() async {
    if (_summary.isEmpty) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/summary_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(_summary);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Summary of ${widget.fileName}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving summary: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    setState(() => _loadingAnswer = true);
    final res = await GeminiService.askQuestion(widget.extractedText, question);
    if (mounted) {
      setState(() {
        _answer = res;
        _loadingAnswer = false;
      });
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
      builder: (context) => Padding(
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
                    onPressed: _isSummarySpeaking ? _stop : _speakSummary,
                    icon: Icon(_isSummarySpeaking ? Icons.pause : Icons.play_arrow_rounded, size: 18),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.85,
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
                    _buildReadAloudTab(),
                    _buildSummarizeTab(),
                    _buildAskTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReadAloudTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
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
                items: TtsService.voices.map((voice) {
                  return DropdownMenuItem(
                    value: voice,
                    child: Text(
                      '${voice['name']} (${voice['locale']})',
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

  Widget _buildSummarizeTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
                      onPressed: _isSummarySpeaking ? _stop : _speakSummary,
                      icon: Icon(
                        _isSummarySpeaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 16,
                      ),
                      label: Text(_isSummarySpeaking ? 'Stop' : 'Listen'),
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

  Widget _buildAskTab() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ask anything about the document...',
                      hintStyle: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _askQuestion(),
                  ),
                ),
                GestureDetector(
                  onTap: _loadingAnswer ? null : _askQuestion,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: _loadingAnswer
                        ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                        : Icon(Icons.arrow_upward_rounded, size: 16, color: theme.colorScheme.onPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_answer.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                _answer,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
        ],
      ),
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