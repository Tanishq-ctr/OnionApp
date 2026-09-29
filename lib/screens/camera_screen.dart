import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/grading_result.dart';
import '../services/grading_service.dart';
import '../services/inference_service.dart';
import '../services/scan_history_service.dart';
import 'results_screen.dart';

/// Full-screen camera preview with a shutter button and gallery picker.
///
/// On capture: runs dual-model inference → grading → saves to history →
/// navigates to results.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isProcessing = false;
  FlashMode _flashMode = FlashMode.off;

  final InferenceService _inferenceService = InferenceService();
  final GradingService _gradingService = GradingService();
  final ScanHistoryService _historyService = ScanHistoryService();
  final ImagePicker _imagePicker = ImagePicker();

  // ──────────────────── lifecycle ────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _inferenceService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ──────────────────── init ────────────────────────────────

  Future<void> _initializeAll() async {
    await _inferenceService.loadModels();
    await _initCamera();
  }

  String? _cameraErrorMessage;

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraErrorMessage =
                'No live camera found on this device or emulator.\n'
                'Please pick an image from your gallery below.';
          });
        }
        return;
      }

      final rear = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _cameraErrorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraErrorMessage = 'Camera init failed: $e\n'
            'Please pick an image from your gallery below.';
      });
    }
  }

  // ──────────────────── flash toggle ─────────────────────────

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _cameraController!.setFlashMode(next);
      setState(() => _flashMode = next);
    } catch (_) {
      // Some devices don't support flash toggle.
    }
  }

  // ──────────────────── capture + inference ──────────────────

  Future<void> _captureAndProcess() async {
    if (_isProcessing || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture) return;

    setState(() => _isProcessing = true);

    try {
      final xfile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await File(xfile.path).readAsBytes();
      await _processImage(imageBytes);
    } catch (e) {
      _showError('Processing failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ──────────────────── gallery picker ───────────────────────

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 90,
      );
      if (xfile == null) return; // User cancelled.

      setState(() => _isProcessing = true);
      final Uint8List imageBytes = await File(xfile.path).readAsBytes();
      await _processImage(imageBytes);
    } catch (e) {
      _showError('Gallery processing failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ──────────────────── shared processing ────────────────────

  Future<void> _processImage(Uint8List imageBytes) async {
    // Run dual-model inference.
    final detections = await _inferenceService.runInference(imageBytes);

    // Grade the results.
    final GradingResult result = _gradingService.grade(detections);

    // Save to history.
    await _historyService.saveRecord(
      imageBytes: imageBytes,
      totalOnions: result.totalOnions,
      gradeACount: result.gradeACount,
      ursCount: result.ursCount,
      classCounts: result.classCounts,
    );

    if (!mounted) return;

    // Navigate to the results screen.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          imageBytes: imageBytes,
          gradingResult: result,
        ),
      ),
    );
  }

  // ──────────────────── UI ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview, error fallback, or loading state.
          if (_isCameraReady && _cameraController != null)
            Center(child: CameraPreview(_cameraController!))
          else if (_cameraErrorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_outlined,
                        color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Live Camera Unavailable',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cameraErrorMessage!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Pick Photo from Gallery'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Initialising camera & models…',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),

          // Top bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black45,
                child: Row(
                  children: [
                    // Back button.
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'OnionGrader',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Flash toggle.
                    IconButton(
                      icon: Icon(
                        _flashMode == FlashMode.off
                            ? Icons.flash_off
                            : Icons.flash_on,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Processing overlay.
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.greenAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analysing onions…',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom bar with gallery + shutter button.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                color: Colors.black54,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Gallery button.
                    GestureDetector(
                      onTap: _isProcessing ? null : _pickFromGallery,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white54, width: 2),
                        ),
                        child: const Icon(Icons.photo_library,
                            color: Colors.white70, size: 26),
                      ),
                    ),

                    // Shutter button.
                    GestureDetector(
                      onTap: _isProcessing ? null : _captureAndProcess,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isProcessing ? Colors.grey : Colors.white,
                          border:
                              Border.all(color: Colors.white70, width: 4),
                        ),
                        child: _isProcessing
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 36, color: Colors.black87),
                      ),
                    ),

                    // Placeholder to balance the row.
                    const SizedBox(width: 48, height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
