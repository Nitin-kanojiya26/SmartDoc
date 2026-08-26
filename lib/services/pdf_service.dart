import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  static Future<String> extractTextFromBytes(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String allText = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: document.pages.count - 1,
      );
      document.dispose();
      return allText;
    } catch (e) {
      throw Exception('Failed to extract text: $e');
    }
  }
}