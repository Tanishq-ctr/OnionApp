import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_record.dart';

/// Manages persistence of scan history records.
///
/// Stores records as JSON in SharedPreferences and images as files
/// in the app's local documents directory.
class ScanHistoryService {
  static const String _prefsKey = 'scan_history';

  /// Saves a new scan record along with its image.
  ///
  /// Returns the created [ScanRecord].
  Future<ScanRecord> saveRecord({
    required Uint8List imageBytes,
    required int totalOnions,
    required int gradeACount,
    required int ursCount,
    required Map<String, int> classCounts,
  }) async {
    final now = DateTime.now();
    final id = 'scan_${now.millisecondsSinceEpoch}';

    // Save the image to local storage.
    final dir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${dir.path}/scans');
    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }
    final imagePath = '${scansDir.path}/$id.jpg';
    await File(imagePath).writeAsBytes(imageBytes);

    final record = ScanRecord(
      id: id,
      timestamp: now,
      imagePath: imagePath,
      totalOnions: totalOnions,
      gradeACount: gradeACount,
      ursCount: ursCount,
      classCounts: classCounts,
    );

    // Load existing records, add new one, and save.
    final records = await getRecords();
    records.insert(0, record); // Newest first.
    await _saveRecords(records);

    return record;
  }

  /// Retrieves all saved scan records, newest first.
  Future<List<ScanRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
    return jsonList
        .map((j) => ScanRecord.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Deletes a specific scan record and its image file.
  Future<void> deleteRecord(String id) async {
    final records = await getRecords();
    final record = records.firstWhere((r) => r.id == id);

    // Delete the image file.
    final imageFile = File(record.imagePath);
    if (await imageFile.exists()) {
      await imageFile.delete();
    }

    records.removeWhere((r) => r.id == id);
    await _saveRecords(records);
  }

  /// Persists the records list to SharedPreferences.
  Future<void> _saveRecords(List<ScanRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(records.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, jsonString);
  }
}
