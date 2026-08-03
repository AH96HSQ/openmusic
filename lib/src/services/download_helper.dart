import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import 'spotify_download_service.dart';

/// Simple download helper for background downloads
/// Uses on-device download service
class DownloadHelper {
  static final DownloadHelper instance = DownloadHelper._internal();
  DownloadHelper._internal();

  final Set<String> _downloadQueue = <String>{};
  final Set<String> _completedDownloads = <String>{};

  // Download completion callbacks
  final List<void Function(String songId)> _downloadCompleteListeners = [];

  bool isDownloading(String songId) => _downloadQueue.contains(songId);
  bool isDownloaded(String songId) => _completedDownloads.contains(songId);

  /// Add a download completion listener
  void addDownloadCompleteListener(void Function(String songId) listener) {
    _downloadCompleteListeners.add(listener);
  }

  /// Remove a download completion listener
  void removeDownloadCompleteListener(void Function(String songId) listener) {
    _downloadCompleteListeners.remove(listener);
  }

  /// Notify all listeners when a download completes (public for external callers)
  void notifyDownloadComplete(String songId) {
    for (final listener in _downloadCompleteListeners) {
      try {
        listener(songId);
      } catch (e) {
        debugPrint('DownloadHelper: Error in download complete listener: $e');
      }
    }
  }

  /// Public method to manually queue a download
  Future<void> downloadSong(String songId) async {
    if (isDownloading(songId) || isDownloaded(songId)) {
      debugPrint(
        'DownloadHelper: Song $songId already downloading or downloaded',
      );
      return;
    }

    await queueDownload(songId);
  }

  void dispose() {
    // Nothing to dispose - no timers anymore
  }

  /// Queue a song for download
  Future<void> queueDownload(String songId) async {
    if (_downloadQueue.contains(songId)) return;

    _downloadQueue.add(songId);
    debugPrint('DownloadHelper: Queued download for $songId');

    try {
      await _processDownload(songId);
    } catch (e) {
      debugPrint('Download error for $songId: $e');
    } finally {
      _downloadQueue.remove(songId);
    }
  }

  /// Process the download for a song - uses on-device download service
  Future<void> _processDownload(String songId) async {
    // Get song data from database
    final songData = await DatabaseHelper.instance.getSong(songId);
    if (songData == null) {
      throw Exception('Song not found in database');
    }

    // Extract Spotify URL
    String? spotifyUrl;
    final extData = songData['ext'];
    if (extData is String && extData.isNotEmpty) {
      final parsed = jsonDecode(extData);
      spotifyUrl = parsed['spotify']?['url'] as String?;
    }

    if (spotifyUrl == null || spotifyUrl.isEmpty) {
      throw Exception('No Spotify URL found for song $songId');
    }

    debugPrint('DownloadHelper: Starting on-device download for $songId');
    debugPrint('DownloadHelper: Spotify URL: $spotifyUrl');

    // Use on-device download service
    final result = await SpotifyDownloadService.instance.downloadSpotifyTrack(
      spotifyUrl,
      onProgress: (written, total) {
        final percent = total != null
            ? (written / total * 100).toStringAsFixed(1)
            : '?';
        debugPrint('DownloadHelper: Download progress $songId: $percent%');
      },
    );

    if (!result.ok) {
      throw Exception('Download failed: ${result.error}');
    }

    // Update database with local file path
    await _updateLocalPath(songId, result.path!);

    debugPrint('DownloadHelper: Downloaded file for $songId to ${result.path}');
    debugPrint('DownloadHelper: File size: ${result.sizeBytes} bytes');

    // Mark as completed
    _completedDownloads.add(songId);
    debugPrint('DownloadHelper: Completed download for $songId');

    // Notify listeners about completion
    notifyDownloadComplete(songId);
  }

  /// Update database local path
  Future<void> _updateLocalPath(String songId, String localPath) async {
    try {
      await DatabaseHelper.instance.updateSong(songId, {
        'on_device_status': 'true',
        'on_device_filename': localPath,
      });
    } catch (e) {
      debugPrint('Error updating local path: $e');
    }
  }
}
