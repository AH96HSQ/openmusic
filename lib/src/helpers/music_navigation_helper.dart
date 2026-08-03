import 'dart:io';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../ui/pages/album_bottom_sheet.dart';
import '../ui/pages/artist_bottom_sheet.dart';
import '../ui/widgets/song_tile.dart';
import '../services/status_message_controller.dart';

/// Helper class for navigation to album and artist details
class MusicNavigationHelper {
  /// Navigate to album from song ID
  static Future<void> goToAlbum(BuildContext context, String songId) async {
    // Show bottom sheet immediately with loading state
    if (context.mounted) {
      await showAlbumBottomSheet(context, songId: songId);
    }
  }

  /// Navigate to artist from song ID
  static Future<void> goToArtist(BuildContext context, String songId) async {
    // Show bottom sheet immediately with loading state
    if (context.mounted) {
      await showArtistBottomSheet(context, songId: songId);
    }
  }

  /// Create popup menu options for album and artist navigation
  static List<PopupMenuOption> createNavigationMenuOptions(
    BuildContext context,
    String songId,
  ) {
    return [
      PopupMenuOption(
        id: 'go_to_album',
        label: 'Go to Album',
        onSelected: () => goToAlbum(context, songId),
      ),
      PopupMenuOption(
        id: 'go_to_artist',
        label: 'Go to Artist',
        onSelected: () => goToArtist(context, songId),
      ),
    ];
  }

  /// Create popup menu items for album and artist navigation (for PopupMenuButton)
  static List<PopupMenuItem<String>> createNavigationMenuItems(
    BuildContext context,
    String songId,
  ) {
    return [
      PopupMenuItem<String>(
        value: 'go_to_album',
        child: const Row(
          children: [
            Icon(Icons.album),
            SizedBox(width: 12),
            Text('Go to Album'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'go_to_artist',
        child: const Row(
          children: [
            Icon(Icons.person),
            SizedBox(width: 12),
            Text('Go to Artist'),
          ],
        ),
      ),
    ];
  }

  /// Handle popup menu item selection for navigation
  static Future<void> handleNavigationMenuSelection(
    BuildContext context,
    String value,
    String songId,
  ) async {
    switch (value) {
      case 'go_to_album':
        await goToAlbum(context, songId);
        break;
      case 'go_to_artist':
        await goToArtist(context, songId);
        break;
    }
  }

  /// Remove a song from library (deletes offline file and database entry)
  /// Returns true if the song was removed, false if cancelled
  /// [onRemoved] is called after successful removal to allow refreshing UI
  static Future<bool> removeFromLibrary(
    BuildContext context,
    String songId,
    String? songTitle, {
    VoidCallback? onRemoved,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
          'Are you sure you want to remove "${songTitle ?? 'this song'}" from your library? This will also delete any offline files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      // Get song to check for offline file
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song != null) {
        // Delete offline file if exists
        final filePath = song['on_device_filename'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            debugPrint(
              'MusicNavigationHelper: Deleted offline file: $filePath',
            );
          }
        }
      }

      // Delete from database
      await DatabaseHelper.instance.deleteSong(songId);

      StatusMessageController.instance.showMessage(
        'Removed "${songTitle ?? 'song'}" from library',
        duration: const Duration(milliseconds: 1500),
      );

      // Call the refresh callback
      onRemoved?.call();

      return true;
    } catch (e) {
      debugPrint('MusicNavigationHelper: Error removing song: $e');
      StatusMessageController.instance.showMessage(
        'Failed to remove song',
        duration: const Duration(milliseconds: 1800),
      );
      return false;
    }
  }

  /// Create a popup menu option for removing from library
  /// Only returns the option if the song is NOT a device file
  static PopupMenuOption? createRemoveFromLibraryOption(
    BuildContext context,
    String songId,
    String? songTitle,
    bool isDeviceFile, {
    VoidCallback? onRemoved,
  }) {
    if (isDeviceFile) return null;

    return PopupMenuOption(
      id: 'remove_from_library',
      label: 'Remove from Library',
      onSelected: () =>
          removeFromLibrary(context, songId, songTitle, onRemoved: onRemoved),
    );
  }

  /// Create a popup menu item for removing from library (for PopupMenuButton)
  static PopupMenuItem<String>? createRemoveFromLibraryMenuItem(
    bool isDeviceFile,
  ) {
    if (isDeviceFile) return null;

    return const PopupMenuItem<String>(
      value: 'remove_from_library',
      child: Row(
        children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 12),
          Text('Remove from Library', style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
