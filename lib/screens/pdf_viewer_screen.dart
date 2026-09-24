import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartdoc/services/reading_progress_service.dart';
import 'package:smartdoc/widgets/document_action_popup.dart';
import 'package:smartdoc/services/tts_service.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfViewerScreen extends StatefulWidget {
  final String fileName;
  final Uint8List pdfBytes;
  final String extractedText;
  final String localPath;

  const PdfViewerScreen({
    super.key,
    required this.fileName,
    required this.pdfBytes,
    required this.extractedText,
    required this.localPath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _controller = PdfViewerController();
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 1;
  final ValueNotifier<String?> _selectedPdfText = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (widget.pdfBytes.isEmpty && !kIsWeb) {
        throw Exception('PDF file is empty or corrupted.');
      }

      final savedPage = await ReadingProgressService.getCurrentPage(widget.localPath);
      final savedTotal = await ReadingProgressService.getTotalPages(widget.localPath);
      _currentPage = savedPage;
      _totalPages = savedTotal > 0 ? savedTotal : 1;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _saveCurrentProgress() {
    if (widget.localPath.isNotEmpty) {
      ReadingProgressService.saveProgress(
        widget.localPath,
        _currentPage,
        _totalPages,
      );
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // Ensure valid filename by replacing invalid characters if necessary
      final safeName = widget.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${directory.path}/$safeName');
      await file.writeAsBytes(widget.pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Document: ${widget.fileName}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading PDF: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ValueListenableBuilder<String?>(
            valueListenable: _selectedPdfText,
            builder: (context, selectedText, child) {
              if (selectedText != null && selectedText.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.blueAccent),
                  tooltip: 'Read Selected Text',
                  onPressed: () async {
                    await TtsService.speak(selectedText);
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _downloadPdf,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: DocumentActionPopup(
                    fileName: widget.fileName,
                    extractedText: widget.extractedText,
                    selectedText: _selectedPdfText.value,
                    onClose: () => Navigator.pop(context),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
        ),
      )
          : _error != null
          ? _buildErrorView()
          : Stack(
        children: [
          Builder(
            builder: (context) {
              final pdfView = SfPdfViewer.memory(
                widget.pdfBytes,
                controller: _controller,
                onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                  setState(() {
                    _totalPages = details.document.pages.count;
                  });
                  _saveCurrentProgress();
                  if (_totalPages > 1 && _currentPage > 1 && _currentPage <= _totalPages) {
                    _controller.jumpToPage(_currentPage);
                  }
                },
                onPageChanged: (PdfPageChangedDetails details) {
                  setState(() {
                    _currentPage = details.newPageNumber;
                  });
                  _saveCurrentProgress();
                },
                onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
                  if (details.selectedText == null && _selectedPdfText.value != null) {
                     // small delay to avoid flicker if they are just adjusting selection
                     Future.delayed(const Duration(milliseconds: 100), () {
                        _selectedPdfText.value = details.selectedText;
                     });
                  } else {
                     _selectedPdfText.value = details.selectedText;
                  }
                },
              );

              if (Theme.of(context).brightness == Brightness.dark) {
                return ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ]),
                  child: pdfView,
                );
              }
              return pdfView;
            },
          ),
        ],
      ),
      floatingActionButton: !_isLoading && _error == null
          ? FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: DocumentActionPopup(
                fileName: widget.fileName,
                extractedText: widget.extractedText,
                selectedText: _selectedPdfText.value,
                onClose: () => Navigator.pop(context),
              ),
            ),
          );
        },
        backgroundColor: theme.colorScheme.primary,
        child: Icon(Icons.menu_rounded, color: theme.colorScheme.onPrimary),
      )
          : null,
    );
  }

  Widget _buildErrorView() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading document',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.textTheme.bodyLarge?.color,
                  side: BorderSide(color: theme.colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Go Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveCurrentProgress();
    _controller.dispose();
    _selectedPdfText.dispose();
    super.dispose();
  }
}