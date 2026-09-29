import 'dart:math';

import '../models/detection.dart';
import '../models/grading_result.dart';

/// Computes Grade A / URS percentages from a merged list of detections.
///
/// **Roles**
/// - `onion` detections are the individual onions.
/// - Every other label (`rotten`, `sprout`, `double_split`, `damaged`) is a
///   defect.
///
/// **Defect ↔ onion matching:** defects are usually small boxes *inside* a
/// big onion box, so IoU is the wrong measure (a small patch on a large onion
/// has a tiny IoU). We use `intersection / min(areaDefect, areaOnion)`
/// instead: high when the defect lies inside the onion, and also high when a
/// large defect box (e.g. a rotten onion) covers a whole onion.
///
/// **Undersized heuristic:** an `onion` box whose area is below
/// [undersizeRatio] × the mean `onion` area of the scan (needs ≥ 2 onions).
///
/// **Grade A:** onion with no matched defect and not undersized.
/// **URS:** everything else.
class GradingService {
  /// An onion is undersized if `area < meanArea * undersizeRatio`.
  static const double undersizeRatio = 0.5;

  /// Minimum overlap (see class doc) for a defect to be attached to an onion.
  static const double defectOverlapThreshold = 0.5;

  /// Labels that are NOT individual onions.
  static const String _onionLabel = 'onion';

  GradingResult grade(List<Detection> detections) {
    final onions = <Detection>[];
    final defects = <Detection>[];

    for (final d in detections) {
      if (d.label == _onionLabel) {
        onions.add(d);
      } else {
        defects.add(d);
      }
    }

    final defectiveOnionIdx = <int>{};

    // ── 1. Attach each defect to the onion it overlaps most ──
    final standaloneDefects = <Detection>[];

    for (final defect in defects) {
      int bestIdx = -1;
      double bestOverlap = 0.0;

      for (int i = 0; i < onions.length; i++) {
        final o = _overlap(onions[i], defect);
        if (o > bestOverlap) {
          bestOverlap = o;
          bestIdx = i;
        }
      }

      if (bestIdx != -1 && bestOverlap >= defectOverlapThreshold) {
        defectiveOnionIdx.add(bestIdx);
      } else {
        // Defect with no onion box (model missed the onion itself).
        // Count it as one rejected onion — but only once if several
        // defect boxes sit on the same spot.
        final alreadyCounted = standaloneDefects
            .any((s) => _overlap(s, defect) >= defectOverlapThreshold);
        if (!alreadyCounted) standaloneDefects.add(defect);
      }
    }

    // ── 2. Undersized heuristic (onion boxes only) ──
    final undersizedIndices = <int>[]; // indices into `detections`

    if (onions.length >= 2) {
      final meanArea =
          onions.fold<double>(0.0, (sum, d) => sum + d.area) / onions.length;

      for (int i = 0; i < onions.length; i++) {
        if (onions[i].area < meanArea * undersizeRatio) {
          final allIndex = detections.indexOf(onions[i]);
          if (allIndex != -1) undersizedIndices.add(allIndex);
          defectiveOnionIdx.add(i);
        }
      }
    }

    // ── 3. Totals ──
    final standaloneCount = standaloneDefects.length;
    final totalOnions = onions.length + standaloneCount;
    final ursCount = defectiveOnionIdx.length + standaloneCount;
    final gradeACount = totalOnions - ursCount;

    // ── 4. Per-class counts for the results screen / report ──
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

  /// `intersection area / area of the smaller box`.
  double _overlap(Detection a, Detection b) {
    final xStart = max(a.left, b.left);
    final yStart = max(a.top, b.top);
    final xEnd = min(a.right, b.right);
    final yEnd = min(a.bottom, b.bottom);

    if (xEnd <= xStart || yEnd <= yStart) return 0.0;

    final intersection = (xEnd - xStart) * (yEnd - yStart);
    // Use clamped-box areas so boxes poking past the image edge don't skew it.
    final areaA = (a.right - a.left) * (a.bottom - a.top);
    final areaB = (b.right - b.left) * (b.bottom - b.top);
    final smaller = min(areaA, areaB);

    return smaller <= 0 ? 0.0 : intersection / smaller;
  }
}