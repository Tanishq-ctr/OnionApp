import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';

/// Loads both YOLOv8 TFLite models, runs inference on a captured image,
/// parses the YOLO output tensors, applies NMS, and merges results
/// according to the dual-model strategy described in the project README.
///
/// **Dual-model merge rule:**
/// - Model 1 (veg) → keep all classes: onion, double_split, rotten, sprout
/// - Model 2 (onion2) → keep only `damaged`; discard its onion/rotten outputs
class InferenceService {
  // ──────────────────────── constants ────────────────────────
  static const int _inputSize = 640;

  /// Minimum confidence to keep a detection.
  static const double confThreshold = 0.20;

  /// IoU threshold for Non-Maximum Suppression.
  static const double nmsIouThreshold = 0.45;

  // ──────────────────────── state ────────────────────────────
  Interpreter? _vegInterpreter;
  Interpreter? _onion2Interpreter;

  List<String> _vegLabels = [];
  List<String> _onion2Labels = [];

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // ──────────────────── lifecycle ────────────────────────────

  /// Loads both models and their label files from Flutter assets.
  /// Call once during app startup.
  Future<void> loadModels() async {
    if (_isLoaded) return;

    _vegInterpreter = await Interpreter.fromAsset('assets/veg_model.tflite');
    _onion2Interpreter =
        await Interpreter.fromAsset('assets/onion2_model.tflite');

    _vegLabels = await _loadLabels('assets/veg_model.txt');
    _onion2Labels = await _loadLabels('assets/onion2_model.txt');

    _isLoaded = true;
  }

  /// Releases model resources.
  void dispose() {
    _vegInterpreter?.close();
    _onion2Interpreter?.close();
    _isLoaded = false;
  }

  // ───────────────────── public API ──────────────────────────

  /// Runs both models on [imageBytes] (a JPEG/PNG file's raw bytes),
  /// merges and NMS-filters the results, and returns a flat detection list.
  Future<List<Detection>> runInference(Uint8List imageBytes) async {
    if (!_isLoaded) {
      throw StateError('Models not loaded — call loadModels() first.');
    }

    // Decode and preprocess the image.
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw ArgumentError('Could not decode image bytes.');

    // Run Model 1 (veg).
    final vegRaw = _runModel(_vegInterpreter!, decoded, _vegLabels.length);
    final vegDetections =
        _parseOutput(vegRaw, _vegLabels, 'veg');

    // Run Model 2 (onion2).
    final onion2Raw =
        _runModel(_onion2Interpreter!, decoded, _onion2Labels.length);
    final onion2Detections =
        _parseOutput(onion2Raw, _onion2Labels, 'onion2');

    // Merge: keep all from Model 1, only 'damaged' from Model 2.
    final merged = <Detection>[
      ...vegDetections,
      ...onion2Detections.where((d) => d.label == 'damaged'),
    ];

    // Apply per-class NMS across the merged set.
    return _nms(merged);
  }

  // ──────────────────── preprocessing ────────────────────────

  /// Converts a resized [img.Image] (640×640) into a float32 tensor
  /// shaped `[1, 640, 640, 3]` with pixel values normalised to [0, 1].
  List<List<List<List<double>>>> _imageToFloat32Input(
      img.Image image, List<int> shape) {
    final isNCHW = shape[1] == 3;
    final h = isNCHW ? shape[2] : shape[1];
    final w = isNCHW ? shape[3] : shape[2];

    final resized = img.copyResize(image, width: w, height: h);

    return List.generate(1, (_) {
      if (isNCHW) {
        return List.generate(3, (c) {
          return List.generate(h, (y) {
            return List.generate(w, (x) {
              final pixel = resized.getPixel(x, y);
              if (c == 0) return pixel.r / 255.0;
              if (c == 1) return pixel.g / 255.0;
              return pixel.b / 255.0;
            });
          });
        });
      } else {
        return List.generate(h, (y) {
          return List.generate(w, (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          });
        });
      }
    });
  }

  // ──────────────────── model runner ─────────────────────────

  /// Runs a single TFLite interpreter and returns the raw output tensor
  /// as a 2-D list: either `[numClasses+4][8400]` or `[8400][numClasses+4]`.
  ///
  /// YOLOv8 TFLite output shape is typically `[1, numClasses+4, 8400]`.
  /// Some exports produce `[1, 8400, numClasses+4]`. We auto-detect.
  List<List<double>> _runModel(
      Interpreter interpreter, img.Image rawImage, int numClasses) {
    // Generate the exact input tensor shape requested by the model.
    final inputTensor = interpreter.getInputTensor(0);
    final input = _imageToFloat32Input(rawImage, inputTensor.shape);

    // Query the output tensor shape to allocate correctly.
    final outputTensor = interpreter.getOutputTensor(0);
    final shape = outputTensor.shape; // e.g. [1, 8, 8400] or [1, 8400, 8]

    final dim1 = shape[1];
    final dim2 = shape[2];

    // Allocate output buffer matching the model's declared shape.
    final output = List.generate(
      1,
      (_) => List.generate(dim1, (_) => List.filled(dim2, 0.0)),
    );

    interpreter.run(input, output);

    // Determine orientation: we need rows = anchors, cols = cx/cy/w/h + scores.
    // YOLO outputs are usually [attrs, anchors] or [anchors, attrs].
    // Anchors (e.g., 8400) is always the much larger dimension.
    final attrs = min(dim1, dim2);
    final anchors = max(dim1, dim2);

    if (dim1 == attrs && dim2 == anchors) {
      // Shape is [1, attrs, anchors] — transpose to [anchors][attrs].
      return _transpose(output[0], attrs, anchors);
    } else {
      // Shape is [1, anchors, attrs] — already in the orientation we want.
      return output[0];
    }
  }

  /// Transposes a 2-D list from [rows][cols] to [cols][rows].
  List<List<double>> _transpose(List<List<double>> matrix, int rows, int cols) {
    return List.generate(cols, (c) {
      return List.generate(rows, (r) => matrix[r][c]);
    });
  }

  // ──────────────────── output parsing ───────────────────────

  /// Parses the YOLO output (already in `[anchors, attrs]` orientation)
  /// into a list of [Detection] objects, filtering by [confThreshold].
  ///
  /// Each row: `[cx, cy, w, h, score_cls0, score_cls1, ...]`
  List<Detection> _parseOutput(
      List<List<double>> output, List<String> labels, String modelName) {
    final detections = <Detection>[];
    final numClasses = labels.length;

    for (final row in output) {
      // row[0..3] = cx, cy, w, h (normalised to 0–1 relative to 640).
      // row[4..4+numClasses-1] = per-class scores.

      // Find the best class.
      double maxScore = -1;
      int bestClass = 0;
      final availableClasses = row.length - 4;
      final classesToRead = min(numClasses, availableClasses);

      for (int c = 0; c < classesToRead; c++) {
        final score = row[4 + c];
        if (score > maxScore) {
          maxScore = score;
          bestClass = c;
        }
      }

      if (maxScore < confThreshold) continue;

      final rawCx = row[0];
      final rawCy = row[1];
      final rawW = row[2];
      final rawH = row[3];

      // Auto-detect if coordinates are raw pixels (0..640) or normalized (0..1)
      final isNormalized =
          rawCx <= 1.0 && rawCy <= 1.0 && rawW <= 1.0 && rawH <= 1.0;
      final scale = isNormalized ? 1.0 : _inputSize.toDouble();

      final cx = rawCx / scale;
      final cy = rawCy / scale;
      final w = rawW / scale;
      final h = rawH / scale;

      detections.add(Detection(
        label: labels[bestClass],
        confidence: maxScore,
        x: cx,
        y: cy,
        w: w,
        h: h,
        sourceModel: modelName,
      ));
    }

    return detections;
  }

  // ──────────────────── NMS ──────────────────────────────────

  /// Greedy per-class Non-Maximum Suppression.
  List<Detection> _nms(List<Detection> detections) {
    // Group by label.
    final groups = <String, List<Detection>>{};
    for (final d in detections) {
      groups.putIfAbsent(d.label, () => []).add(d);
    }

    final kept = <Detection>[];
    for (final group in groups.values) {
      // Sort descending by confidence.
      group.sort((a, b) => b.confidence.compareTo(a.confidence));

      final selected = <Detection>[];
      final suppressed = List.filled(group.length, false);

      for (int i = 0; i < group.length; i++) {
        if (suppressed[i]) continue;
        selected.add(group[i]);

        for (int j = i + 1; j < group.length; j++) {
          if (suppressed[j]) continue;
          if (_iou(group[i], group[j]) > nmsIouThreshold) {
            suppressed[j] = true;
          }
        }
      }
      kept.addAll(selected);
    }

    return kept;
  }

  /// Computes Intersection-over-Union between two detections.
  double _iou(Detection a, Detection b) {
    final xOverlapStart = max(a.left, b.left);
    final yOverlapStart = max(a.top, b.top);
    final xOverlapEnd = min(a.right, b.right);
    final yOverlapEnd = min(a.bottom, b.bottom);

    if (xOverlapEnd <= xOverlapStart || yOverlapEnd <= yOverlapStart) {
      return 0.0;
    }

    final intersection =
        (xOverlapEnd - xOverlapStart) * (yOverlapEnd - yOverlapStart);
    final areaA = a.area;
    final areaB = b.area;
    final union = areaA + areaB - intersection;

    return union <= 0 ? 0.0 : intersection / union;
  }

  // ──────────────────── helpers ──────────────────────────────

  /// Loads a newline-separated label file from Flutter assets.
  Future<List<String>> _loadLabels(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
