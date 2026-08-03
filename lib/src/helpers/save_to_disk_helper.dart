import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../services/status_message_controller.dart';

/// Helper class for saving offline songs to user-selected locations
class SaveToDiskHelper {
  /// Save a song file to a user-selected directory
  /// Returns true if successful, false otherwise
  static Future<bool> saveToDisk({
    required BuildContext context,
    required String songId,
    required String? sourceFilePath,
    required String? songTitle,
    required String? artistName,
  }) async {
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      StatusMessageController.instance.showMessage(
        'Song file not available offline',
        duration: const Duration(milliseconds: 2000),
      );
      return false;
    }

    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      StatusMessageController.instance.showMessage(
        'Song file not found',
        duration: const Duration(milliseconds: 2000),
      );
      return false;
    }

    try {
      // Let user pick a directory, starting from Downloads if possible
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose where to save the song',
        initialDirectory: await _getDefaultDownloadsPath(),
      );

      if (selectedDirectory == null) {
        // User cancelled
        return false;
      }

      // Generate a safe filename
      final safeTitle = _sanitizeFilename(songTitle ?? 'Unknown');
      final safeArtist = _sanitizeFilename(artistName ?? 'Unknown Artist');
      final extension = path.extension(sourceFilePath);
      final filename = '$safeArtist - $safeTitle$extension';

      final destinationPath = path.join(selectedDirectory, filename);
      final destinationFile = File(destinationPath);

      // Check if file already exists
      if (await destinationFile.exists()) {
        if (!context.mounted) return false;

        final overwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('File exists'),
            content: Text(
              'A file named "$filename" already exists. Overwrite it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Overwrite'),
              ),
            ],
          ),
        );

        if (overwrite != true) {
          return false;
        }
      }

      // Copy the file
      await sourceFile.copy(destinationPath);

      StatusMessageController.instance.showMessage(
        'Saved to $selectedDirectory',
        duration: const Duration(milliseconds: 2500),
      );

      return true;
    } catch (e) {
      debugPrint('SaveToDiskHelper: Error saving file: $e');
      StatusMessageController.instance.showMessage(
        'Failed to save file',
        duration: const Duration(milliseconds: 2000),
      );
      return false;
    }
  }

  /// Get the default Downloads directory path
  static Future<String?> _getDefaultDownloadsPath() async {
    try {
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final downloadsPath = path.join(userProfile, 'Downloads');
          if (await Directory(downloadsPath).exists()) {
            return downloadsPath;
          }
        }
      } else if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final downloadsPath = path.join(home, 'Downloads');
          if (await Directory(downloadsPath).exists()) {
            return downloadsPath;
          }
        }
      } else if (Platform.isAndroid) {
        // On Android, FilePicker will handle the default location
        return '/storage/emulated/0/Download';
      }
    } catch (e) {
      debugPrint('SaveToDiskHelper: Error getting downloads path: $e');
    }
    return null;
  }

  /// Sanitize a string to be used as a filename
  static String _sanitizeFilename(String input) {
    // Remove or replace characters that are invalid in filenames
    return input
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
