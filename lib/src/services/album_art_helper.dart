import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';

/// Helper class for downloading and caching album artwork locally.
///
/// Uses a singleton pattern with in-memory tracking to prevent duplicate downloads
/// and persists file paths to the database for fast lookups.
class AlbumArtHelper {
  AlbumArtHelper._();
  static final AlbumArtHelper instance = AlbumArtHelper._();

  final Map<String, bool> _downloadingIds = {};
  final Map<String, String> _pathCache =
      {}; // In-memory cache of songId -> local path
  final Map<String, String> _urlCache =
      {}; // In-memory cache of songId -> network URL
  Directory? _artworkDir;

  /// Get the artwork directory, creating it if needed
  Future<Directory> _getArtworkDir() async {
    if (_artworkDir != null) return _artworkDir!;

    final docDir = await getApplicationDocumentsDirectory();
    _artworkDir = Directory('${docDir.path}/artwork');

    if (!await _artworkDir!.exists()) {
      await _artworkDir!.create(recursive: true);
    }

    return _artworkDir!;
  }

  /// Check if status indicates artwork is downloaded
  bool _isDownloaded(dynamic status) {
    if (status == null) return false;
    final s = status.toString();
    return s == 'true' || s == 'downloaded' || s == '1';
  }

  /// Get the local artwork path if it exists on device
  Future<String?> getLocalArtworkPath(String songId) async {
    // Check in-memory cache first
    if (_pathCache.containsKey(songId)) {
      final cachedPath = _pathCache[songId]!;
      // Verify file still exists
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
      // File was deleted, remove from cache
      _pathCache.remove(songId);
    }

    try {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song == null) {
        return null;
      }

      final status = song['album_art_on_device_status'];
      final filename = song['album_art_on_device_filename']?.toString();

      if (_isDownloaded(status) && filename != null && filename.isNotEmpty) {
        final artworkDir = await _getArtworkDir();
        final path = '${artworkDir.path}/$filename';

        if (await File(path).exists()) {
          _pathCache[songId] = path; // Cache the result
          return path;
        } else {
          // File doesn't exist despite status saying downloaded - reset status
          // This allows the background downloader to pick it up
          await DatabaseHelper.instance.updateSong(songId, {
            'album_art_on_device_status': 'false',
            'album_art_on_device_filename': '',
          });
        }
      }
    } catch (e) {
      debugPrint('AlbumArtHelper: Error getting local path for $songId: $e');
    }
    return null;
  }

  /// Get the network URL for artwork
  Future<String?> getArtworkUrl(String songId) async {
    // Check in-memory cache first
    if (_urlCache.containsKey(songId)) {
      return _urlCache[songId];
    }

    try {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song == null) return null;

      // Try artwork_largest first, then image_url
      final artworkLargest = song['artwork_largest']?.toString();
      if (artworkLargest != null && artworkLargest.isNotEmpty) {
        _urlCache[songId] = artworkLargest; // Cache the result
        return artworkLargest;
      }

      final imageUrl = song['image_url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        _urlCache[songId] = imageUrl; // Cache the result
        return imageUrl;
      }
    } catch (e) {
      debugPrint('AlbumArtHelper: Error getting artwork URL for $songId: $e');
    }
    return null;
  }

  /// Download artwork for a song and cache it locally
  Future<String?> downloadArtworkForSong(
    String songId, {
    bool forceRetry = false,
  }) async {
    // Skip if already downloading
    if (_downloadingIds[songId] == true) {
      return null;
    }

    try {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song == null) {
        return null;
      }

      final status = song['album_art_on_device_status'];
      final existingFilename = song['album_art_on_device_filename']?.toString();

      // Check if already downloaded and file exists (unless forcing retry)
      if (!forceRetry &&
          _isDownloaded(status) &&
          existingFilename != null &&
          existingFilename.isNotEmpty) {
        final artworkDir = await _getArtworkDir();
        final existingPath = '${artworkDir.path}/$existingFilename';

        if (await File(existingPath).exists()) {
          _pathCache[songId] = existingPath;
          return existingPath;
        }
      }

      // Get artwork URL
      final artworkUrl = await getArtworkUrl(songId);
      if (artworkUrl == null || artworkUrl.isEmpty) {
        return null;
      }

      _downloadingIds[songId] = true;

      final artworkDir = await _getArtworkDir();
      final filename = 'album_art_$songId.jpg';
      final filePath = '${artworkDir.path}/$filename';

      // Download the image
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(artworkUrl));
      final response = await request.close();

      if (response.statusCode == 200) {
        final file = File(filePath);
        final bytes = await response.fold<List<int>>(
          [],
          (previous, element) => previous..addAll(element),
        );
        await file.writeAsBytes(bytes);

        // Update database
        await DatabaseHelper.instance.updateSong(songId, {
          'album_art_on_device_status': 'true',
          'album_art_on_device_filename': filename,
        });

        // Update in-memory cache
        _pathCache[songId] = filePath;

        return filePath;
      }
    } catch (e) {
      debugPrint('AlbumArtHelper: Error downloading artwork for $songId: $e');
    } finally {
      _downloadingIds.remove(songId);
    }

    return null;
  }

  /// Batch download album art for multiple songs.
  Future<void> downloadBatch(List<Map<String, dynamic>> songs) async {
    for (final song in songs) {
      final songId = song['id']?.toString();
      if (songId == null) continue;

      final status = song['album_art_on_device_status'];
      if (_isDownloaded(status)) continue;

      await downloadArtworkForSong(songId);

      // Small delay between downloads
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Download missing artwork for all songs in database
  /// This runs in background and doesn't block UI
  Future<void> downloadAllMissingArtwork() async {
    debugPrint(
      'AlbumArtHelper: Starting background download of missing artwork...',
    );

    try {
      final songs = await DatabaseHelper.instance.getAllSongs();
      final artworkDir = await _getArtworkDir();
      int downloaded = 0;
      int skipped = 0;

      for (final song in songs) {
        final songId = song['id']?.toString();
        if (songId == null) continue;

        // Check if already downloaded AND file actually exists
        final status = song['album_art_on_device_status'];
        final filename = song['album_art_on_device_filename']?.toString();
        if (_isDownloaded(status) && filename != null && filename.isNotEmpty) {
          final filePath = '${artworkDir.path}/$filename';
          if (await File(filePath).exists()) {
            skipped++;
            continue;
          }
          // File doesn't exist despite status saying downloaded - need to re-download
          debugPrint(
            'AlbumArtHelper: File missing for $songId despite status=downloaded, re-downloading...',
          );
        }

        // Skip if no artwork URL available
        final artworkUrl =
            song['artwork_largest']?.toString() ??
            song['image_url']?.toString();
        if (artworkUrl == null || artworkUrl.isEmpty) {
          continue;
        }

        // Download in background
        final result = await downloadArtworkForSong(songId);
        if (result != null) {
          downloaded++;
        }

        // Small delay to avoid overwhelming the network
        await Future.delayed(const Duration(milliseconds: 50));
      }

      debugPrint(
        'AlbumArtHelper: Background download complete - downloaded: $downloaded, already cached: $skipped',
      );
    } catch (e) {
      debugPrint('AlbumArtHelper: Error in downloadAllMissingArtwork: $e');
    }
  }

  /// Clear cached artwork directory reference
  void clearCache() {
    _artworkDir = null;
    _downloadingIds.clear();
    _pathCache.clear();
    _urlCache.clear();
  }
}
