import '../models/detection.dart';
import '../models/grading_result.dart';

/// Applies the undersized heuristic and computes Grade A / URS percentages
/// from a merged list of detections.
///
/// **Undersized heuristic:** An onion is flagged as undersized if its
/// bounding-box area is less than [undersizeRatio] × the mean area of all
/// 'onion'-class detections in the same scan. This is a relative
/// batch-comparison approach — no physical reference object needed.
///
/// **Grade A:** Onions with zero overlapping defect boxes AND not undersized.
/// **URS:** Everything else (defective or undersized).
class GradingService {
  /// Ratio threshold for the undersized heuristic.
  /// An onion is undersized if `area < meanArea * undersizeRatio`.
  ///
  /// Default 0.5 = flag anything below 50 % of the batch average.
  static const double undersizeRatio = 0.5;

  /// IoU threshold used to associate a defect box with an onion box.
  /// If a defect overlaps an onion by more than this fraction, the onion
  /// is considered defective.
  static const double defectOverlapThreshold = 0.3;

  /// Processes raw detections into a full [GradingResult].
  GradingResult grade(List<Detection> detections) {
    // ── 1. Separate Model 1 (veg model) detections from Model 2 (onion2) 'damaged' detections ──
    final m1Detections = <Detection>[];
    final m2DamagedDetections = <Detection>[];

    for (final d in detections) {
      if (d.sourceModel == 'veg' || d.label != 'damaged') {
        m1Detections.add(d);
      } else {
        m2DamagedDetections.add(d);
      }
    }

    final defectiveM1Indices = <int>{};

    // Mark Model 1 detections whose labels are defects ('rotten', 'sprout', 'double_split')
    for (int i = 0; i < m1Detections.length; i++) {
      final label = m1Detections[i].label;
      if (label == 'rotten' || label == 'sprout' || label == 'double_split') {
        defectiveM1Indices.add(i);
      }
    }

    // ── 2. Undersized heuristic ──
    final undersizedIndices = <int>[];

    if (m1Detections.length >= 2) {
      final meanArea =
          m1Detections.fold<double>(0.0, (sum, d) => sum + d.area) /
              m1Detections.length;

      for (int i = 0; i < m1Detections.length; i++) {
        if (m1Detections[i].area < meanArea * undersizeRatio) {
          final allIndex = detections.indexOf(m1Detections[i]);
          if (allIndex != -1) {
            undersizedIndices.add(allIndex);
          }
          defectiveM1Indices.add(i);
        }
      }
    }

    // ── 3. Find which Model 1 onions overlap with Model 2 damaged boxes ──
    int standaloneDamagedCount = 0;

    for (final damaged in m2DamagedDetections) {
      bool overlapped = false;
      for (int i = 0; i < m1Detections.length; i++) {
        if (_iou(m1Detections[i], damaged) > defectOverlapThreshold) {
          defectiveM1Indices.add(i);
          overlapped = true;
          break;
        }
      }
      if (!overlapped) {
        standaloneDamagedCount++;
      }
    }

    final totalOnions = m1Detections.length + standaloneDamagedCount;
    final ursCount = defectiveM1Indices.length + standaloneDamagedCount;
    final gradeACount = totalOnions - ursCount;

    // ── 5. Per-class counts for the report ──
    final classCounts = <String, int>{};
    for (final d in detections) {
      classCounts[d.label] = (classCounts[d.label] ?? 0) + 1;
    }
    classCounts['undersized'] = undersizedIndices.length;

    return GradingResult(
      allDetections: detections,
      undersizedIndices: undersizedIndices,
      totalOnions: totalOnions,
      gradeACount: gradeACount,
      ursCount: ursCount,
      classCounts: classCounts,
    );
  }

  /// Computes Intersection-over-Union between two detections.
  double _iou(Detection a, Detection b) {
    final xStart = a.left > b.left ? a.left : b.left;
    final yStart = a.top > b.top ? a.top : b.top;
    final xEnd = a.right < b.right ? a.right : b.right;
    final yEnd = a.bottom < b.bottom ? a.bottom : b.bottom;

    if (xEnd <= xStart || yEnd <= yStart) return 0.0;

    final intersection = (xEnd - xStart) * (yEnd - yStart);
    final union = a.area + b.area - intersection;

    return union <= 0 ? 0.0 : intersection / union;
  }
}
