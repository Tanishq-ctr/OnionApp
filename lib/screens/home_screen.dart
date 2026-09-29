import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scan_record.dart';
import '../services/scan_history_service.dart';
import 'camera_screen.dart';

/// Main home screen showing a scrollable list of past scan records,
/// styled similarly to Adobe Scan's document list view.
///
/// A floating action button at the bottom provides Camera + Gallery access.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScanHistoryService _historyService = ScanHistoryService();
  List<ScanRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final records = await _historyService.getRecords();
    if (!mounted) return;
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Scan?'),
        content: const Text('This will permanently remove this scan record.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _historyService.deleteRecord(record.id);
      await _loadRecords();
    }
  }

  // ──────────────────── navigation ────────────────────────────

  Future<void> _openCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    // Reload records when returning from camera/results flow.
    await _loadRecords();
  }

  // ──────────────────── UI ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.eco, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              'OnionGrader',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState(theme)
              : _buildRecordsList(theme),
      floatingActionButton: _buildFab(theme),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ──────────────────── empty state ──────────────────────────

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_outlined,
              size: 80, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No scans yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the camera button below to grade your first batch!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ──────────────────── records list ─────────────────────────

  Widget _buildRecordsList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _records.length,
        itemBuilder: (context, index) => _buildRecordCard(_records[index], theme),
      ),
    );
  }

  Widget _buildRecordCard(ScanRecord record, ThemeData theme) {
    final dateStr = DateFormat('dd MMM yyyy').format(record.timestamp);
    final timeStr = DateFormat('hh:mm a').format(record.timestamp);
    final imageFile = File(record.imagePath);
    final qualityColor = _qualityColor(record.qualityLabel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            // TODO: Navigate to detailed results view for this record.
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Thumbnail.
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: imageFile.existsSync()
                        ? Image.file(imageFile, fit: BoxFit.cover)
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image, size: 40),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Details.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Onion Scan $dateStr',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _statChip(
                            '${record.totalOnions} onions',
                            theme.colorScheme.primary,
                            theme,
                          ),
                          const SizedBox(width: 6),
                          _statChip(
                            '${record.gradeAPercent.toStringAsFixed(0)}% A',
                            Colors.green,
                            theme,
                          ),
                          const SizedBox(width: 6),
                          _statChip(
                            record.qualityLabel,
                            qualityColor,
                            theme,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Delete action.
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error.withValues(alpha: 0.6)),
                  onPressed: () => _deleteRecord(record),
                  tooltip: 'Delete scan',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ──────────────────── FAB ──────────────────────────────────

  Widget _buildFab(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'camera_fab',
          onPressed: _openCamera,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          child: const Icon(Icons.camera_alt, size: 28),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: 'gallery_fab',
          onPressed: () => _openCamera(), // Gallery handled inside CameraScreen.
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: const Icon(Icons.photo_library, size: 28),
        ),
      ],
    );
  }

  // ──────────────────── helpers ──────────────────────────────

  Color _qualityColor(String label) {
    switch (label) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Fair':
        return Colors.orange;
      case 'Poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'OnionGrader',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.eco, size: 48, color: Colors.green),
      children: const [
        Text(
          'AI-powered onion quality grading application using dual '
          'YOLOv8 TFLite models. Detects onions, classifies defects '
          '(rotten, sprouted, damaged, double-split), and generates '
          'PDF quality reports.',
        ),
      ],
    );
  }
}
