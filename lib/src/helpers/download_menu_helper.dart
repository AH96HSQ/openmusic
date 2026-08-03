import 'dart:io';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../services/download_settings_service.dart';
import '../services/download_queue_service.dart';
import '../ui/widgets/song_tile.dart';

/// Helper class for download/redownload menu options
class DownloadMenuHelper {
  /// Get method display name (short)
  static String getMethodName(DownloadMethodId method) {
    return DownloadSettingsService.getMethodName(method);
  }

  /// Create a PopupMenuOption for download/redownload with dynamic label
  /// This uses labelBuilder to determine the correct label based on song data
  static PopupMenuOption createDownloadMenuOption({
    required String songId,
    VoidCallback? onComplete,
  }) {
    return PopupMenuOption(
      id: 'download_auto',
      label: 'Download', // Fallback label
      labelBuilder: (songData) {
        if (songData == null) return 'Download';
        final isDevice =
            songData['source'] == 'device' ||
            songData['is_device_file'] == 'true';
        if (isDevice) return ''; // Won't be shown
        final isOffline =
            songData['on_device_status'] == 'true' &&
            songData['on_device_filename'] != null &&
            (songData['on_device_filename'] as String).isNotEmpty;
        return isOffline ? 'Redownload' : 'Download';
      },
      onSelected: () async {
        final song = await DatabaseHelper.instance.getSong(songId);
        if (song == null) return;

        final isDeviceFile =
            song['source'] == 'device' || song['is_device_file'] == 'true';
        if (isDeviceFile) return;

        final isOfflineAvailable =
            song['on_device_status'] == 'true' &&
            song['on_device_filename'] != null &&
            (song['on_device_filename'] as String).isNotEmpty;

        final songTitle = song['title'] as String?;

        if (isOfflineAvailable) {
          await redownloadSongAuto(songId, songTitle: songTitle);
        } else {
          await downloadSongAuto(songId, songTitle: songTitle);
        }
        onComplete?.call();
      },
    );
  }

  /// Create both download options: main download + choose method
  /// Returns a list of PopupMenuOptions
  static List<PopupMenuOption> createDownloadMenuOptions({
    required String songId,
    required BuildContext context,
    VoidCallback? onComplete,
  }) {
    return [
      createDownloadMenuOption(songId: songId, onComplete: onComplete),
      PopupMenuOption(
        id: 'download_choose_method',
        label: 'Choose Method',
        onSelected: () async {
          final song = await DatabaseHelper.instance.getSong(songId);
          if (song == null) return;

          final isDeviceFile =
              song['source'] == 'device' || song['is_device_file'] == 'true';
          if (isDeviceFile) return;

          final isOfflineAvailable =
              song['on_device_status'] == 'true' &&
              song['on_device_filename'] != null &&
              (song['on_device_filename'] as String).isNotEmpty;

          final songTitle = song['title'] as String?;

          // Show method selection dialog - check if context is still valid
          if (!context.mounted) return;
          final method = await showMethodSelectionDialog(context);
          if (method == null) return;

          if (isOfflineAvailable) {
            await redownloadSongWithMethod(
              songId,
              method,
              songTitle: songTitle,
            );
          } else {
            await downloadSongWithMethod(songId, method, songTitle: songTitle);
          }
          onComplete?.call();
        },
      ),
    ];
  }

  /// Show a dialog to select download method
  static Future<DownloadMethodId?> showMethodSelectionDialog(
    BuildContext context,
  ) async {
    final methodOrder = DownloadSettingsService.instance.methodOrder;

    return showDialog<DownloadMethodId>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Download Method'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: methodOrder.map((method) {
            final name = DownloadSettingsService.getMethodName(method);
            return ListTile(
              leading: _getMethodIcon(method),
              title: Text(name),
              onTap: () => Navigator.of(ctx).pop(method),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Delete offline file for a song (used before redownload)
  static Future<bool> deleteOfflineFile(String songId) async {
    try {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song == null) return false;

      final filePath = song['on_device_filename'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('DownloadMenuHelper: Deleted offline file: $filePath');
        }
      }

      // Update database to mark as not offline
      await DatabaseHelper.instance.updateSong(songId, {
        'on_device_status': 'false',
        'on_device_filename': '',
      });

      return true;
    } catch (e) {
      debugPrint('DownloadMenuHelper: Error deleting offline file: $e');
      return false;
    }
  }

  /// Download a song using auto method (uses queue)
  /// If a download is in progress, this song is added to the front (priority)
  static Future<void> downloadSongAuto(
    String songId, {
    String? songTitle,
  }) async {
    DownloadQueueService.instance.addToQueue(
      songId: songId,
      songTitle: songTitle,
      isRedownload: false,
      priority: DownloadQueueService.instance.isProcessing,
    );
  }

  /// Download a song using a specific method (uses queue)
  /// If a download is in progress, this song is added to the front (priority)
  static Future<void> downloadSongWithMethod(
    String songId,
    DownloadMethodId method, {
    String? songTitle,
  }) async {
    DownloadQueueService.instance.addToQueue(
      songId: songId,
      songTitle: songTitle,
      method: method,
      isRedownload: false,
      priority: DownloadQueueService.instance.isProcessing,
    );
  }

  /// Redownload a song using auto method
  /// If a download is in progress, this song is added to the front (priority)
  static Future<void> redownloadSongAuto(
    String songId, {
    String? songTitle,
  }) async {
    DownloadQueueService.instance.addToQueue(
      songId: songId,
      songTitle: songTitle,
      isRedownload: true,
      priority: DownloadQueueService.instance.isProcessing,
    );
  }

  /// Redownload a song using a specific method
  /// If a download is in progress, this song is added to the front (priority)
  static Future<void> redownloadSongWithMethod(
    String songId,
    DownloadMethodId method, {
    String? songTitle,
  }) async {
    DownloadQueueService.instance.addToQueue(
      songId: songId,
      songTitle: songTitle,
      method: method,
      isRedownload: true,
      priority: DownloadQueueService.instance.isProcessing,
    );
  }

  /// Download multiple songs (batch download)
  static Future<void> downloadMultipleSongs(
    List<String> songIds, {
    DownloadMethodId? method,
    bool isRedownload = false,
  }) async {
    DownloadQueueService.instance.addMultipleToQueue(
      songIds: songIds,
      method: method,
      isRedownload: isRedownload,
    );
  }

  /// Show method selection popup at a given position
  static Future<DownloadMethodId?> showMethodSelectionPopup(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final methodOrder = DownloadSettingsService.instance.methodOrder;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return null;

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    return showMenu<DownloadMethodId>(
      context: context,
      position: position,
      items: methodOrder.map((method) {
        return PopupMenuItem<DownloadMethodId>(
          value: method,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _getMethodIcon(method),
              const SizedBox(width: 12),
              Text(getMethodName(method)),
              const SizedBox(width: 8),
              Text(
                '(${DownloadSettingsService.getMethodDescription(method)})',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Get icon for a method
  static Widget _getMethodIcon(DownloadMethodId method) {
    IconData iconData;
    switch (method) {
      case DownloadMethodId.sra:
        iconData = Icons.speed;
      case DownloadMethodId.dsra:
        iconData = Icons.cloud_download;
      case DownloadMethodId.smp:
        iconData = Icons.music_note;
    }
    return Icon(iconData, size: 20);
  }

  /// Create a PopupMenuItem for download/redownload with arrow
  static PopupMenuItem<String> createDownloadMenuItem(
    bool isOfflineAvailable,
    bool isDeviceFile,
  ) {
    if (isDeviceFile) {
      return const PopupMenuItem<String>(
        enabled: false,
        height: 0,
        value: '',
        child: SizedBox.shrink(),
      );
    }

    final isRedownload = isOfflineAvailable;
    final label = isRedownload ? 'Redownload' : 'Download';
    final icon = isRedownload ? Icons.refresh : Icons.download;

    return PopupMenuItem<String>(
      value: isRedownload ? 'redownload_direct' : 'download_direct',
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.arrow_right, size: 20),
          ),
        ],
      ),
    );
  }

  /// Handle download menu selection
  /// Direct click = auto download, no dialog
  static Future<void> handleDownloadMenuSelection(
    BuildContext context,
    String value,
    String songId,
    String? songTitle, {
    VoidCallback? onComplete,
  }) async {
    if (value == 'download_direct' || value == 'download_menu') {
      await downloadSongAuto(songId, songTitle: songTitle);
      onComplete?.call();
      return;
    }

    if (value == 'redownload_direct' || value == 'redownload_menu') {
      await redownloadSongAuto(songId, songTitle: songTitle);
      onComplete?.call();
      return;
    }
  }

  /// Check if a song is offline available
  static bool isOfflineAvailable(Map<String, dynamic>? song) {
    if (song == null) return false;
    final isDevice =
        song['source'] == 'device' || song['is_device_file'] == 'true';
    if (isDevice) return false;
    return song['on_device_status'] == 'true' &&
        song['on_device_filename'] != null &&
        (song['on_device_filename'] as String).isNotEmpty;
  }

  /// Check if a song is a device file
  static bool isDeviceFile(Map<String, dynamic>? song) {
    if (song == null) return false;
    return song['source'] == 'device' || song['is_device_file'] == 'true';
  }
}
