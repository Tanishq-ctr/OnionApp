import 'detection.dart';

/// Aggregated grading output for one scan (one captured image).
///
/// Produced by [GradingService] and consumed by both the results screen
/// and the PDF report generator.
class GradingResult {
  /// All merged, NMS-filtered detections from both models.
  final List<Detection> allDetections;

  /// Indices into [allDetections] for onions flagged as undersized.
  final List<int> undersizedIndices;

  /// Total number of individual onions detected (label == 'onion' from
  /// Model 1, plus any defect boxes that represent separate onions).
  final int totalOnions;

  /// Count of onions with zero defects and not undersized.
  final int gradeACount;

  /// Count of onions that are defective or undersized.
  final int ursCount;

  /// Grade A percentage (0–100).
  double get gradeAPercent =>
      totalOnions == 0 ? 0.0 : (gradeACount / totalOnions) * 100;

  /// URS (undersize / rejected / substandard) percentage (0–100).
  double get ursPercent =>
      totalOnions == 0 ? 0.0 : (ursCount / totalOnions) * 100;

  /// Per-class counts for the report breakdown.
  final Map<String, int> classCounts;

  const GradingResult({
    required this.allDetections,
    required this.undersizedIndices,
    required this.totalOnions,
    required this.gradeACount,
    required this.ursCount,
    required this.classCounts,
  });

  @override
  String toString() =>
      'GradingResult(total=$totalOnions, A=$gradeACount '
      '(${gradeAPercent.toStringAsFixed(1)}%), '
      'URS=$ursCount (${ursPercent.toStringAsFixed(1)}%))';
}
