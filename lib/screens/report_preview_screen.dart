import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/grading_result.dart';
import '../utils/report_generator.dart';

/// Full-screen PDF preview with a share button in the app bar.
class ReportPreviewScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final GradingResult gradingResult;

  const ReportPreviewScreen({
    super.key,
    required this.imageBytes,
    required this.gradingResult,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _buildPdf();
  }

  Future<void> _buildPdf() async {
    try {
      final bytes = await ReportGenerator.buildPdfBytes(
        imageBytes: widget.imageBytes,
        gradingResult: widget.gradingResult,
      );
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sharePdf() async {
    if (_pdfBytes == null) return;
    try {
      await ReportGenerator.sharePdfBytes(_pdfBytes!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Preview'),
        actions: [
          if (_pdfBytes != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share / Save PDF',
              onPressed: _sharePdf,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Building report…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to build report:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      );
    }

    return PdfPreview(
      build: (_) => _pdfBytes!,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: 'onion_report.pdf',
    );
  }
}
