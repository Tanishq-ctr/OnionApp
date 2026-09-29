/// Represents a single object detection from a YOLO TFLite model.
class Detection {
  /// Human-readable class label (e.g. 'onion', 'rotten', 'damaged').
  final String label;

  /// Confidence score in range [0.0, 1.0].
  final double confidence;

  /// Bounding box center-x, normalized to [0, 1] relative to image width.
  final double x;

  /// Bounding box center-y, normalized to [0, 1] relative to image height.
  final double y;

  /// Bounding box width, normalized to [0, 1] relative to image width.
  final double w;

  /// Bounding box height, normalized to [0, 1] relative to image height.
  final double h;

  /// Which model produced this detection: 'veg' or 'onion2'.
  final String sourceModel;

  /// Normalized bounding-box area (w × h). Used by the undersized heuristic.
  double get area => w * h;

  /// Left edge (x - w/2), clamped to [0, 1].
  double get left => (x - w / 2).clamp(0.0, 1.0);

  /// Top edge (y - h/2), clamped to [0, 1].
  double get top => (y - h / 2).clamp(0.0, 1.0);

  /// Right edge (x + w/2), clamped to [0, 1].
  double get right => (x + w / 2).clamp(0.0, 1.0);

  /// Bottom edge (y + h/2), clamped to [0, 1].
  double get bottom => (y + h / 2).clamp(0.0, 1.0);

  const Detection({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.sourceModel,
  });

  @override
  String toString() =>
      'Detection($label, conf=${confidence.toStringAsFixed(2)}, '
      'box=[$x, $y, $w, $h], src=$sourceModel)';
}
