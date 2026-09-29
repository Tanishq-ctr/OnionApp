import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../models/grading_result.dart';
import 'report_preview_screen.dart';

/// Displays the captured image with colored bounding-box overlays and
/// a stats breakdown card (Grade A %, URS %, per-class counts).
class ResultsScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final GradingResult gradingResult;

  const ResultsScreen({
    super.key,
    required this.imageBytes,
    required this.gradingResult,
  });

  // ──────────────────── colour coding ───────────────────────

  static const Map<String, Color> _labelColors = {
    'onion': Colors.green,
    'double_split': Colors.red,
    'rotten': Colors.redAccent,
    'sprout': Colors.orange,
    'damaged': Colors.deepOrange,
  };

  static const Color _undersizedColor = Colors.yellow;

  Color _colorForDetection(Detection d, bool isUndersized) {
    if (isUndersized && d.label == 'onion') return _undersizedColor;
    return _labelColors[d.label] ?? Colors.white;
  }

  // ──────────────────── UI ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final result = gradingResult;
    final undersizedSet = result.undersizedIndices.toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generate Report',
            onPressed: () => _generateReport(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Annotated image ──
            AspectRatio(
              aspectRatio: 1.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(imageBytes, fit: BoxFit.contain),
                      CustomPaint(
                        painter: _BoundingBoxPainter(
                          detections: result.allDetections,
                          undersizedIndices: undersizedSet,
                          colorFn: _colorForDetection,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Grade summary card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Quality Summary',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      _summaryRow(
                        'Total Onions',
                        '${result.totalOnions}',
                      ),
                      _summaryRow(
                        'Grade A',
                        '${result.gradeACount}  '
                            '(${result.gradeAPercent.toStringAsFixed(1)} %)',
                        color: Colors.green,
                      ),
                      _summaryRow(
                        'URS (Rejected)',
                        '${result.ursCount}  '
                            '(${result.ursPercent.toStringAsFixed(1)} %)',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Per-class breakdown ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Breakdown',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const Divider(),
                      ...result.classCounts.entries.map(
                        (e) => _summaryRow(
                          _formatLabel(e.key),
                          '${e.value}',
                          color: _labelColors[e.key] ?? _undersizedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Generate report button ──
            FilledButton.icon(
              onPressed: () => _generateReport(context),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Generate PDF Report'),
            ),

            const SizedBox(height: 8),

            // ── Legend ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _legendDot(Colors.green, 'Grade A'),
                  _legendDot(Colors.red, 'Rotten'),
                  _legendDot(Colors.redAccent, 'Double Split'),
                  _legendDot(Colors.orange, 'Sprout'),
                  _legendDot(Colors.deepOrange, 'Damaged'),
                  _legendDot(Colors.yellow, 'Undersized'),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ──────────────────── report action ───────────────────────

  Future<void> _generateReport(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportPreviewScreen(
          imageBytes: imageBytes,
          gradingResult: gradingResult,
        ),
      ),
    );
  }

  // ──────────────────── widgets ──────────────────────────────

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _formatLabel(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ──────────────────── bounding-box painter ───────────────────

class _BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Set<int> undersizedIndices;
  final Color Function(Detection, bool) colorFn;

  _BoundingBoxPainter({
    required this.detections,
    required this.undersizedIndices,
    required this.colorFn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      final isUndersized = undersizedIndices.contains(i);
      final color = colorFn(d, isUndersized);

      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );

      // Draw bounding box.
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, boxPaint);

      // Draw label background.
      final labelText =
          '${d.label} ${(d.confidence * 100).toStringAsFixed(0)}%';
      final textStyle = ui.TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      );
      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle())
        ..pushStyle(textStyle)
        ..addText(labelText);
      final paragraph = paragraphBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: 200));

      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - paragraph.height - 4,
        paragraph.longestLine + 8,
        paragraph.height + 4,
      );
      canvas.drawRect(bgRect, Paint()..color = color.withValues(alpha: 0.7));
      canvas.drawParagraph(paragraph, Offset(rect.left + 4, bgRect.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) => true;
}
