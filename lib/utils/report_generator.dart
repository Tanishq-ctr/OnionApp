import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/grading_result.dart';

/// Builds a shareable PDF quality report from a [GradingResult] and the
/// captured image bytes.
///
/// The report includes:
/// - Scan timestamp
/// - Captured image
/// - Per-class detection counts
/// - Grade A % / URS %
/// - CC BY 4.0 data attribution (required by training dataset licenses)
class ReportGenerator {
  ReportGenerator._();

  /// Builds the PDF and returns the raw bytes (for previewing).
  static Future<Uint8List> buildPdfBytes({
    required Uint8List imageBytes,
    required GradingResult gradingResult,
  }) async {
    return _buildPdf(imageBytes, gradingResult);
  }

  /// Shares an already-built PDF via the system share / print dialog.
  static Future<void> sharePdfBytes(Uint8List pdfBytes) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: _filename());
  }

  /// Generates a PDF and opens the system share / print dialog.
  static Future<void> generateAndShare({
    required Uint8List imageBytes,
    required GradingResult gradingResult,
  }) async {
    final pdfDoc = await _buildPdf(imageBytes, gradingResult);
    await Printing.sharePdf(bytes: pdfDoc, filename: _filename());
  }

  // ──────────────────── PDF construction ─────────────────────

  static Future<Uint8List> _buildPdf(
    Uint8List imageBytes,
    GradingResult result,
  ) async {
    final pdf = pw.Document(
      title: 'Onion Quality Report',
      author: 'OnionGrader App',
    );

    final image = pw.MemoryImage(imageBytes);
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _header(now),
        footer: (context) => _footer(context),
        build: (context) => [
          // ── Title ──
          pw.Center(
            child: pw.Text(
              'Onion Quality Grading Report',
              style: const pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Generated: ${_formatDate(now)}',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey),
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Captured image ──
          pw.Center(
            child: pw.Container(
              width: 300,
              height: 300,
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Summary table ──
          pw.Text(
            'Quality Summary',
            style: const pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _summaryTable(result),
          pw.SizedBox(height: 20),

          // ── Detection breakdown ──
          pw.Text(
            'Detection Breakdown',
            style: const pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _breakdownTable(result),
          pw.SizedBox(height: 24),

          // ── Attribution ──
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Data Attribution (CC BY 4.0)',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Training data sourced from "veg" by Onion Grading NX and '
                  '"Onion2.0" by Rishabhs Workspace, Roboflow Universe, '
                  'licensed under CC BY 4.0.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ──────────────────── tables ───────────────────────────────

  static pw.Widget _summaryTable(GradingResult result) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.green50),
      headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      headers: ['Metric', 'Value'],
      data: [
        ['Total Onions Detected', '${result.totalOnions}'],
        [
          'Grade A',
          '${result.gradeACount}  (${result.gradeAPercent.toStringAsFixed(1)} %)'
        ],
        [
          'URS (Rejected)',
          '${result.ursCount}  (${result.ursPercent.toStringAsFixed(1)} %)'
        ],
      ],
    );
  }

  static pw.Widget _breakdownTable(GradingResult result) {
    final rows = result.classCounts.entries
        .map((e) => [_formatLabel(e.key), '${e.value}'])
        .toList();

    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColors.orange50),
      headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      headers: ['Class', 'Count'],
      data: rows,
    );
  }

  // ──────────────────── header / footer ─────────────────────

  static pw.Widget _header(DateTime now) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('OnionGrader',
              style:
                  const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(_formatDate(now),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('MIT License',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ],
      ),
    );
  }

  // ──────────────────── helpers ──────────────────────────────

  static String _filename() {
    final now = DateTime.now();
    final stamp = '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return 'onion_report_$stamp.pdf';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  static String _formatLabel(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
