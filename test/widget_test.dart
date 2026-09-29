import 'package:flutter_test/flutter_test.dart';
import 'package:onion_app/models/detection.dart';
import 'package:onion_app/services/grading_service.dart';

void main() {
  group('GradingService', () {
    final service = GradingService();

    test('returns zero totals for empty detection list', () {
      final result = service.grade([]);

      expect(result.totalOnions, 0);
      expect(result.gradeACount, 0);
      expect(result.ursCount, 0);
      expect(result.gradeAPercent, 0.0);
      expect(result.ursPercent, 0.0);
    });

    test('single healthy onion is 100% Grade A', () {
      final detections = [
        const Detection(
          label: 'onion',
          confidence: 0.9,
          x: 0.5, y: 0.5, w: 0.3, h: 0.3,
          sourceModel: 'veg',
        ),
      ];

      final result = service.grade(detections);

      expect(result.totalOnions, 1);
      expect(result.gradeACount, 1);
      expect(result.ursCount, 0);
      expect(result.gradeAPercent, 100.0);
    });

    test('onion overlapping a rotten defect is marked URS', () {
      final detections = [
        const Detection(
          label: 'onion',
          confidence: 0.9,
          x: 0.5, y: 0.5, w: 0.3, h: 0.3,
          sourceModel: 'veg',
        ),
        const Detection(
          label: 'rotten',
          confidence: 0.8,
          x: 0.5, y: 0.5, w: 0.25, h: 0.25,
          sourceModel: 'veg',
        ),
      ];

      final result = service.grade(detections);

      expect(result.totalOnions, 1);
      expect(result.gradeACount, 0);
      expect(result.ursCount, 1);
      expect(result.ursPercent, 100.0);
    });

    test('undersized heuristic flags small onions in a batch', () {
      final detections = [
        // Normal-sized onion.
        const Detection(
          label: 'onion',
          confidence: 0.9,
          x: 0.3, y: 0.5, w: 0.3, h: 0.3,
          sourceModel: 'veg',
        ),
        // Normal-sized onion.
        const Detection(
          label: 'onion',
          confidence: 0.85,
          x: 0.7, y: 0.5, w: 0.3, h: 0.3,
          sourceModel: 'veg',
        ),
        // Very small onion — should be flagged undersized.
        const Detection(
          label: 'onion',
          confidence: 0.8,
          x: 0.5, y: 0.8, w: 0.05, h: 0.05,
          sourceModel: 'veg',
        ),
      ];

      final result = service.grade(detections);

      expect(result.totalOnions, 3);
      expect(result.undersizedIndices, isNotEmpty);
      expect(result.ursCount, greaterThan(0));
      expect(result.gradeACount, lessThan(3));
    });

    test('classCounts includes all detected labels', () {
      final detections = [
        const Detection(
          label: 'onion', confidence: 0.9,
          x: 0.3, y: 0.5, w: 0.2, h: 0.2, sourceModel: 'veg',
        ),
        const Detection(
          label: 'sprout', confidence: 0.7,
          x: 0.7, y: 0.5, w: 0.1, h: 0.1, sourceModel: 'veg',
        ),
        const Detection(
          label: 'damaged', confidence: 0.6,
          x: 0.5, y: 0.3, w: 0.1, h: 0.1, sourceModel: 'onion2',
        ),
      ];

      final result = service.grade(detections);

      expect(result.classCounts['onion'], 1);
      expect(result.classCounts['sprout'], 1);
      expect(result.classCounts['damaged'], 1);
      expect(result.classCounts.containsKey('undersized'), isTrue);
    });
  });
}
