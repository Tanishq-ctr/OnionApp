import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection.dart';

/// Loads both YOLOv8 TFLite models, runs inference on a captured image,
/// parses the YOLO output tensors, applies NMS, and merges results
/// according to the dual-model strategy described in the project README.
///
/// **Dual-model merge rule:**
/// - Model 1 (veg)    → keep all classes: onion, double_split, rotten, sprout
/// - Model 2 (onion2) → keep only the defect classes `damaged` and `rotten`;
///                      its `onion` output is discarded.
///
/// **Changes vs. v1 (fixes for "defective onion graded as Grade A"):**
/// 1. Multi-label parsing: every class that clears its OWN threshold becomes
///    a detection. v1 kept only the argmax class per anchor, so on a whole
///    onion the `onion` class always won and defect scores were thrown away.
/// 2. Per-class thresholds (defect classes use a lower bar than `onion`).
/// 3. Letterbox preprocessing (keeps aspect ratio, like YOLO training) instead
///    of stretching the photo to a square.
/// 4. EXIF orientation is baked in before inference.
/// 5. `rotten` from Model 2 is kept as well as `damaged`.
/// 6. Optional debug logging of the best raw score per class.
class InferenceService {
  // ──────────────────────── constants ────────────────────────

  /// Print the best raw score per class for every scan (debug builds only).
  /// Handy for checking whether defect classes fire at all.
  static const bool debugLogging = true;

  /// Per-class confidence thresholds. Tune the defect values on real photos:
  /// lower = catches more defects but risks false rejects.
  static const Map<String, double> classThresholds = {
    'onion': 0.30,
    'double_split': 0.15,
    'rotten': 0.15,
    'sprout': 0.15,
    'damaged': 0.15,
  };

  /// Used for any class name not listed above.
  static const double defaultThreshold = 0.25;

  /// IoU threshold for Non-Maximum Suppression.
  static const double nmsIouThreshold = 0.45;

  /// Max boxes kept per class before NMS (keeps NMS fast at low thresholds).
  static const int _maxCandidatesPerClass = 100;

  /// Model 2 classes that are merged into the final result.
  static const Set<String> _onion2KeepLabels = {'damaged', 'rotten'};

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
  ///
  /// All boxes are normalised (0..1) relative to the ORIGINAL image, so the
  /// results screen and PDF report can draw them exactly as before.
  Future<List<Detection>> runInference(Uint8List imageBytes) async {
    if (!_isLoaded) {
      throw StateError('Models not loaded — call loadModels() first.');
    }

    var decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw ArgumentError('Could not decode image bytes.');

    // Apply EXIF rotation so the model sees the photo upright.
    decoded = img.bakeOrientation(decoded);

    final vegDetections =
    _infer(_vegInterpreter!, decoded, _vegLabels, 'veg');
    final onion2Detections =
    _infer(_onion2Interpreter!, decoded, _onion2Labels, 'onion2');

    // Merge: everything from Model 1, only defect classes from Model 2.
    final merged = <Detection>[
      ...vegDetections,
      ...onion2Detections.where((d) => _onion2KeepLabels.contains(d.label)),
    ];

    // Per-class NMS across the merged set (also de-duplicates `rotten`
    // when both models fire on the same spot).
    return _nms(merged);
  }

  // ──────────────────── single-model pipeline ────────────────

  List<Detection> _infer(
      Interpreter interpreter,
      img.Image image,
      List<String> labels,
      String modelName,
      ) {
    final inputShape = interpreter.getInputTensor(0).shape;
    final prepared = _prepareInput(image, inputShape);

    final rows = _runModel(interpreter, prepared.tensor);
    return _parseOutput(rows, labels, modelName, prepared.letterbox);
  }

  // ──────────────────── preprocessing ────────────────────────

  /// Letterboxes [image] into the model's input size (aspect ratio kept,
  /// grey padding) and converts it to a float32 tensor in [0, 1].
  _Prepared _prepareInput(img.Image image, List<int> shape) {
    final isNCHW = shape[1] == 3;
    final inH = isNCHW ? shape[2] : shape[1];
    final inW = isNCHW ? shape[3] : shape[2];

    final origW = image.width;
    final origH = image.height;

    final scale = min(inW / origW, inH / origH);
    final newW = max(1, (origW * scale).round());
    final newH = max(1, (origH * scale).round());
    final padX = ((inW - newW) / 2).floor();
    final padY = ((inH - newH) / 2).floor();

    final resized = img.copyResize(
      image,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );

    const double grey = 114 / 255.0; // standard YOLO letterbox colour

    // Returns channel value (0..1) at model-space pixel (x, y).
    double value(int x, int y, int c) {
      final rx = x - padX;
      final ry = y - padY;
      if (rx < 0 || ry < 0 || rx >= newW || ry >= newH) return grey;
      final p = resized.getPixel(rx, ry);
      if (c == 0) return p.r / 255.0;
      if (c == 1) return p.g / 255.0;
      return p.b / 255.0;
    }

    final tensor = List.generate(1, (_) {
      if (isNCHW) {
        return List.generate(
          3,
              (c) => List.generate(
            inH,
                (y) => List.generate(inW, (x) => value(x, y, c)),
          ),
        );
      } else {
        return List.generate(
          inH,
              (y) => List.generate(
            inW,
                (x) => [value(x, y, 0), value(x, y, 1), value(x, y, 2)],
          ),
        );
      }
    });

    return _Prepared(
      tensor,
      _Letterbox(
        inW: inW,
        inH: inH,
        padX: padX,
        padY: padY,
        newW: newW,
        newH: newH,
      ),
    );
  }

  // ──────────────────── model runner ─────────────────────────

  /// Runs a single TFLite interpreter and returns the raw output as
  /// `[anchors][4 + numClasses]`.
  ///
  /// YOLOv8 TFLite output is usually `[1, 4+numClasses, 8400]`; some exports
  /// give `[1, 8400, 4+numClasses]`. Both are handled.
  List<List<double>> _runModel(
      Interpreter interpreter,
      List<List<List<List<double>>>> input,
      ) {
    final shape = interpreter.getOutputTensor(0).shape;
    final dim1 = shape[1];
    final dim2 = shape[2];

    final output = List.generate(
      1,
          (_) => List.generate(dim1, (_) => List.filled(dim2, 0.0)),
    );

    interpreter.run(input, output);

    final attrs = min(dim1, dim2);
    final anchors = max(dim1, dim2);

    if (dim1 == attrs && dim2 == anchors) {
      return _transpose(output[0], attrs, anchors);
    } else {
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

  /// Parses `[anchors][cx, cy, w, h, score_cls0, score_cls1, ...]` into
  /// detections in ORIGINAL-image normalised coordinates.
  ///
  /// Multi-label: each class whose score clears its own threshold produces a
  /// detection, so a `damaged` score is no longer lost just because `onion`
  /// scored higher on the same anchor.
  List<Detection> _parseOutput(
      List<List<double>> output,
      List<String> labels,
      String modelName,
      _Letterbox lb,
      ) {
    final detections = <Detection>[];
    if (output.isEmpty) return detections;

    final numClasses = labels.length;
    final classesToRead = min(numClasses, output.first.length - 4);

    // Decide ONCE per model whether coordinates are normalised (0..1) or in
    // input pixels, instead of guessing per row.
    double maxCoord = 0;
    for (final row in output) {
      if (row[0] > maxCoord) maxCoord = row[0];
      if (row[1] > maxCoord) maxCoord = row[1];
    }
    final isNormalized = maxCoord <= 1.5;

    final bestPerClass = List<double>.filled(numClasses, 0.0);

    for (final row in output) {
      for (int c = 0; c < classesToRead; c++) {
        final score = row[4 + c];
        if (score > bestPerClass[c]) bestPerClass[c] = score;

        final label = labels[c];
        final threshold = classThresholds[label] ?? defaultThreshold;
        if (score < threshold) continue;

        // Box in model-input pixels.
        final cxPx = isNormalized ? row[0] * lb.inW : row[0];
        final cyPx = isNormalized ? row[1] * lb.inH : row[1];
        final wPx = isNormalized ? row[2] * lb.inW : row[2];
        final hPx = isNormalized ? row[3] * lb.inH : row[3];

        // Undo letterbox → normalised coordinates of the original image.
        final cx = ((cxPx - lb.padX) / lb.newW).clamp(0.0, 1.0);
        final cy = ((cyPx - lb.padY) / lb.newH).clamp(0.0, 1.0);
        final w = (wPx / lb.newW).clamp(0.0, 1.0);
        final h = (hPx / lb.newH).clamp(0.0, 1.0);

        detections.add(Detection(
          label: label,
          confidence: score,
          x: cx,
          y: cy,
          w: w,
          h: h,
          sourceModel: modelName,
        ));
      }
    }

    if (debugLogging && kDebugMode) {
      final buf = StringBuffer('[Inference:$modelName] best raw scores → ');
      for (int c = 0; c < numClasses; c++) {
        buf.write('${labels[c]}=${bestPerClass[c].toStringAsFixed(2)}  ');
      }
      buf.write('| kept ${detections.length} candidates pre-NMS');
      debugPrint(buf.toString());
    }

    return detections;
  }

  // ──────────────────── NMS ──────────────────────────────────

  /// Greedy per-class Non-Maximum Suppression.
  List<Detection> _nms(List<Detection> detections) {
    final groups = <String, List<Detection>>{};
    for (final d in detections) {
      groups.putIfAbsent(d.label, () => []).add(d);
    }

    final kept = <Detection>[];
    for (final group in groups.values) {
      group.sort((a, b) => b.confidence.compareTo(a.confidence));
      final candidates = group.length > _maxCandidatesPerClass
          ? group.sublist(0, _maxCandidatesPerClass)
          : group;

      final selected = <Detection>[];
      final suppressed = List.filled(candidates.length, false);

      for (int i = 0; i < candidates.length; i++) {
        if (suppressed[i]) continue;
        selected.add(candidates[i]);

        for (int j = i + 1; j < candidates.length; j++) {
          if (suppressed[j]) continue;
          if (_iou(candidates[i], candidates[j]) > nmsIouThreshold) {
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
    final union = a.area + b.area - intersection;

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

/// Letterbox geometry for one model input, used to map boxes back to the
/// original image.
class _Letterbox {
  final int inW;
  final int inH;
  final int padX;
  final int padY;
  final int newW;
  final int newH;

  const _Letterbox({
    required this.inW,
    required this.inH,
    required this.padX,
    required this.padY,
    required this.newW,
    required this.newH,
  });
}

class _Prepared {
  final List<List<List<List<double>>>> tensor;
  final _Letterbox letterbox;

  const _Prepared(this.tensor, this.letterbox);
}