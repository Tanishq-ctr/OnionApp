import 'dart:convert';

/// Represents a saved onion grading scan record.
///
/// Stored as JSON in SharedPreferences for scan history.
class ScanRecord {
  /// Unique identifier (timestamp-based).
  final String id;

  /// When the scan was performed.
  final DateTime timestamp;

  /// Path to the saved image file on local storage.
  final String imagePath;

  /// Total onions detected.
  final int totalOnions;

  /// Grade A count.
  final int gradeACount;

  /// URS (rejected) count.
  final int ursCount;

  /// Per-class detection counts.
  final Map<String, int> classCounts;

  /// Grade A percentage.
  double get gradeAPercent =>
      totalOnions == 0 ? 0.0 : (gradeACount / totalOnions) * 100;

  /// URS percentage.
  double get ursPercent =>
      totalOnions == 0 ? 0.0 : (ursCount / totalOnions) * 100;

  /// Overall quality label.
  String get qualityLabel {
    if (totalOnions == 0) return 'No Onions';
    if (gradeAPercent >= 80) return 'Excellent';
    if (gradeAPercent >= 60) return 'Good';
    if (gradeAPercent >= 40) return 'Fair';
    return 'Poor';
  }

  const ScanRecord({
    required this.id,
    required this.timestamp,
    required this.imagePath,
    required this.totalOnions,
    required this.gradeACount,
    required this.ursCount,
    required this.classCounts,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'imagePath': imagePath,
        'totalOnions': totalOnions,
        'gradeACount': gradeACount,
        'ursCount': ursCount,
        'classCounts': classCounts,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        imagePath: json['imagePath'] as String,
        totalOnions: json['totalOnions'] as int,
        gradeACount: json['gradeACount'] as int,
        ursCount: json['ursCount'] as int,
        classCounts: Map<String, int>.from(json['classCounts'] as Map),
      );
}
