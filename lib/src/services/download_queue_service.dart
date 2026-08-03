import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import 'spotify_download_service.dart';
import 'status_message_controller.dart';
import 'download_helper.dart';
import 'download_settings_service.dart';

/// Result of a download operation
class DownloadQueueResult {
  final bool success;
  final String? filePath;
  final String? error;

  const DownloadQueueResult.success(this.filePath)
    : success = true,
      error = null;
  const DownloadQueueResult.failure(this.error)
    : success = false,
      filePath = null;
}

/// Represents a download task in the queue
class DownloadTask {
  final String songId;
  final String? songTitle;
  final DownloadMethodId? specificMethod; // null means auto mode
  final bool isRedownload;
  final Completer<DownloadQueueResult>? completer; // For awaiting completion

  DownloadTask({
    required this.songId,
    this.songTitle,
    this.specificMethod,
    this.isRedownload = false,
    this.completer,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          songId == other.songId;

  @override
  int get hashCode => songId.hashCode;
}

/// Service to manage download queue for multiple songs
class DownloadQueueService extends ChangeNotifier {
  static final DownloadQueueService _instance =
      DownloadQueueService._internal();
  static DownloadQueueService get instance => _instance;

  DownloadQueueService._internal();

  /// Queue of pending downloads
  final Queue<DownloadTask> _queue = Queue<DownloadTask>();

  /// Currently downloading task
  DownloadTask? _currentTask;

  /// Whether the queue is being processed
  bool _isProcessing = false;

  /// Stats for current batch
  int _totalInBatch = 0;
  int _completedInBatch = 0;
  int _failedInBatch = 0;

  /// Map of song IDs to completers for songs being awaited
  final Map<String, Completer<DownloadQueueResult>> _awaitingCompleters = {};

  /// Getters
  bool get isProcessing => _isProcessing;
  int get queueLength => _queue.length;
  int get totalInBatch => _totalInBatch;
  int get completedInBatch => _completedInBatch;
  int get failedInBatch => _failedInBatch;
  DownloadTask? get currentTask => _currentTask;

  /// Check if a song is in the queue or currently downloading
  bool isInQueue(String songId) {
    if (_currentTask?.songId == songId) return true;
    return _queue.any((task) => task.songId == songId);
  }

  /// Add a single song to the download queue
  /// If priority is true, adds to front of queue (for user-initiated downloads during batch)
  void addToQueue({
    required String songId,
    String? songTitle,
    DownloadMethodId? method,
    bool isRedownload = false,
    bool priority = false,
  }) {
    // If already currently downloading this song, do nothing
    if (_currentTask?.songId == songId) {
      debugPrint('DownloadQueue: Song $songId is currently downloading');
      return;
    }

    // If in queue and priority requested, move to front
    if (priority && _queue.any((t) => t.songId == songId)) {
      final existingTask = _queue.firstWhere((t) => t.songId == songId);
      _queue.remove(existingTask);
      _queue.addFirst(existingTask);
      debugPrint('DownloadQueue: Moved $songId to front of queue');
      notifyListeners();
      return;
    }

    // Don't add duplicates
    if (isInQueue(songId)) {
      debugPrint('DownloadQueue: Song $songId already in queue, skipping');
      return;
    }

    final task = DownloadTask(
      songId: songId,
      songTitle: songTitle,
      specificMethod: method,
      isRedownload: isRedownload,
    );

    // Add to front (priority) or back (normal)
    if (priority) {
      _queue.addFirst(task);
    } else {
      _queue.add(task);
    }

    // Update batch count
    if (!_isProcessing) {
      _totalInBatch = 1;
      _completedInBatch = 0;
      _failedInBatch = 0;
    } else {
      _totalInBatch++;
    }

    notifyListeners();
    _processQueue();
  }

  /// Download a song with priority and wait for completion
  /// Returns the result with file path on success
  /// Used by playback controller to download and play immediately
  Future<DownloadQueueResult> downloadAndWait({
    required String songId,
    String? songTitle,
  }) async {
    debugPrint('DownloadQueue.downloadAndWait: Starting for $songId');

    // If already currently downloading this song, wait for it
    if (_currentTask?.songId == songId) {
      debugPrint(
        'DownloadQueue.downloadAndWait: Song is currently downloading, waiting...',
      );
      final completer = Completer<DownloadQueueResult>();
      _awaitingCompleters[songId] = completer;
      return completer.future;
    }

    // If already in queue, move to front and wait
    if (_queue.any((t) => t.songId == songId)) {
      final existingTask = _queue.firstWhere((t) => t.songId == songId);
      _queue.remove(existingTask);
      _queue.addFirst(existingTask);
      debugPrint('DownloadQueue.downloadAndWait: Moved to front, waiting...');
      final completer = Completer<DownloadQueueResult>();
      _awaitingCompleters[songId] = completer;
      return completer.future;
    }

    // Create completer for this download
    final completer = Completer<DownloadQueueResult>();
    _awaitingCompleters[songId] = completer;

    // Create task and add to front
    final task = DownloadTask(
      songId: songId,
      songTitle: songTitle,
      isRedownload: false,
      completer: completer,
    );

    _queue.addFirst(task);

    // Update batch count
    if (!_isProcessing) {
      _totalInBatch = 1;
      _completedInBatch = 0;
      _failedInBatch = 0;
    } else {
      _totalInBatch++;
    }

    notifyListeners();
    _processQueue();

    debugPrint('DownloadQueue.downloadAndWait: Waiting for completion...');
    return completer.future;
  }

  /// Add multiple songs to the download queue
  void addMultipleToQueue({
    required List<String> songIds,
    DownloadMethodId? method,
    bool isRedownload = false,
  }) {
    debugPrint(
      'DownloadQueue.addMultipleToQueue: Received ${songIds.length} songs',
    );
    if (songIds.isEmpty) {
      debugPrint('DownloadQueue.addMultipleToQueue: Empty list, returning');
      return;
    }

    // Filter out duplicates
    final newSongIds = songIds.where((id) => !isInQueue(id)).toList();
    debugPrint(
      'DownloadQueue.addMultipleToQueue: After filtering duplicates: ${newSongIds.length} songs',
    );
    if (newSongIds.isEmpty) {
      StatusMessageController.instance.showMessage(
        'All songs already in queue',
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }

    // Reset batch stats if not processing
    if (!_isProcessing) {
      _totalInBatch = newSongIds.length;
      _completedInBatch = 0;
      _failedInBatch = 0;
    } else {
      _totalInBatch += newSongIds.length;
    }

    for (final songId in newSongIds) {
      _queue.add(
        DownloadTask(
          songId: songId,
          specificMethod: method,
          isRedownload: isRedownload,
        ),
      );
    }

    notifyListeners();

    // Show queued message
    if (newSongIds.length > 1) {
      StatusMessageController.instance.showMessage(
        'Queued ${newSongIds.length} songs for download',
        duration: const Duration(milliseconds: 1500),
      );
    }

    debugPrint('DownloadQueue.addMultipleToQueue: Calling _processQueue');
    _processQueue();
  }

  /// Process the download queue
  Future<void> _processQueue() async {
    debugPrint(
      'DownloadQueue._processQueue: Called, isProcessing=$_isProcessing, queueLength=${_queue.length}',
    );
    if (_isProcessing) {
      debugPrint('DownloadQueue._processQueue: Already processing, returning');
      return;
    }
    if (_queue.isEmpty) {
      debugPrint('DownloadQueue._processQueue: Queue is empty, returning');
      return;
    }

    debugPrint('DownloadQueue._processQueue: Starting to process queue');
    _isProcessing = true;
    notifyListeners();

    while (_queue.isNotEmpty) {
      _currentTask = _queue.removeFirst();
      debugPrint(
        'DownloadQueue._processQueue: Processing task for song ${_currentTask!.songId}',
      );
      notifyListeners();

      final task = _currentTask!;
      final success = await _downloadSong(task);

      if (success) {
        _completedInBatch++;
      } else {
        _failedInBatch++;
      }

      notifyListeners();
    }

    // Show completion message
    _showCompletionMessage();

    _currentTask = null;
    _isProcessing = false;
    notifyListeners();
  }

  /// Download a single song
  Future<bool> _downloadSong(DownloadTask task) async {
    try {
      final song = await DatabaseHelper.instance.getSong(task.songId);
      if (song == null) {
        debugPrint('DownloadQueue: Song ${task.songId} not found');
        return false;
      }

      // Check if it's a device file
      final isDeviceFile =
          song['source'] == 'device' || song['is_device_file'] == 'true';
      if (isDeviceFile) {
        debugPrint(
          'DownloadQueue: Song ${task.songId} is a device file, skipping',
        );
        return false;
      }

      // Get Spotify URL
      final spotifyUrl = _getSpotifyUrl(song, task.songId);
      if (spotifyUrl == null) {
        debugPrint('DownloadQueue: No Spotify URL for ${task.songId}');
        return false;
      }

      final title = task.songTitle ?? song['title'] as String? ?? 'song';

      // Delete existing file if redownload
      if (task.isRedownload) {
        await _deleteOfflineFile(task.songId, song);
      }

      // Calculate current position in queue
      final current = _completedInBatch + _failedInBatch + 1;

      // Determine method
      final method = task.specificMethod != null
          ? DownloadSettingsService.toServiceMethod(task.specificMethod!)
          : SpotifyDownloadService.methodAuto;

      // Download - always pass batch info (even for single = 1/1)
      final result = await SpotifyDownloadService.instance.downloadSpotifyTrack(
        spotifyUrl,
        method: method,
        batchCurrent: current,
        batchTotal: _totalInBatch,
        onProgress: (bytesWritten, totalBytes) {
          if (totalBytes != null && totalBytes > 0) {
            final percentage = ((bytesWritten / totalBytes) * 100).round();
            // Always show with current/total format
            StatusMessageController.instance.showBatchDownloadProgress(
              current: current,
              total: _totalInBatch,
              currentTitle: title,
              currentProgress: percentage,
            );
          }
        },
      );

      // Handle result
      if (result.ok && result.path != null) {
        await DatabaseHelper.instance.updateSong(task.songId, {
          'on_device_status': 'true',
          'on_device_filename': result.path,
        });
        DownloadHelper.instance.notifyDownloadComplete(task.songId);
        debugPrint('DownloadQueue: Downloaded ${task.songId}');

        // Complete awaiting completer if exists
        final completer = _awaitingCompleters.remove(task.songId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(DownloadQueueResult.success(result.path));
        }

        return true;
      } else {
        debugPrint(
          'DownloadQueue: Failed to download ${task.songId}: ${result.error}',
        );

        // Complete awaiting completer with failure if exists
        final completer = _awaitingCompleters.remove(task.songId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(
            DownloadQueueResult.failure(result.error ?? 'Download failed'),
          );
        }

        return false;
      }
    } catch (e) {
      debugPrint('DownloadQueue: Error downloading ${task.songId}: $e');

      // Complete awaiting completer with failure if exists
      final completer = _awaitingCompleters.remove(task.songId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(DownloadQueueResult.failure(e.toString()));
      }

      return false;
    }
  }

  /// Show completion message based on batch results
  void _showCompletionMessage() {
    if (_totalInBatch == 1) {
      // Single download
      if (_completedInBatch == 1) {
        StatusMessageController.instance.showDownloaded();
      } else {
        StatusMessageController.instance.showAllAttemptsFailed();
      }
    } else {
      // Batch download
      if (_failedInBatch == 0) {
        StatusMessageController.instance.showMessage(
          'Downloaded $_completedInBatch songs',
          duration: const Duration(milliseconds: 2500),
        );
      } else if (_completedInBatch == 0) {
        StatusMessageController.instance.showMessage(
          'All $_totalInBatch downloads failed',
          duration: const Duration(milliseconds: 2500),
        );
      } else {
        StatusMessageController.instance.showMessage(
          'Downloaded $_completedInBatch of $_totalInBatch songs',
          duration: const Duration(milliseconds: 2500),
        );
      }
    }
  }

  /// Get Spotify URL from song data
  String? _getSpotifyUrl(Map<String, dynamic> song, String songId) {
    String? spotifyUrl;

    final extData = song['ext'];
    if (extData is String && extData.isNotEmpty) {
      try {
        final parsed = Map<String, dynamic>.from(
          (extData.startsWith('{'))
              ? (Map<String, dynamic>.from(
                  const JsonDecoder().convert(extData) as Map,
                ))
              : {},
        );
        spotifyUrl = parsed['spotify']?['url'] as String?;
      } catch (_) {}
    }

    if (spotifyUrl == null || spotifyUrl.isEmpty) {
      spotifyUrl = song['spotify_url'] as String?;
    }

    if (spotifyUrl == null || spotifyUrl.isEmpty) {
      final spotifyId = song['spotify_id'] as String? ?? songId;
      if (spotifyId.isNotEmpty) {
        spotifyUrl = 'https://open.spotify.com/track/$spotifyId';
      }
    }

    return (spotifyUrl != null && spotifyUrl.isNotEmpty) ? spotifyUrl : null;
  }

  /// Delete offline file before redownload
  Future<void> _deleteOfflineFile(
    String songId,
    Map<String, dynamic> song,
  ) async {
    try {
      final filePath = song['on_device_filename'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('DownloadQueue: Deleted offline file: $filePath');
        }
      }
      await DatabaseHelper.instance.updateSong(songId, {
        'on_device_status': 'false',
        'on_device_filename': '',
      });
    } catch (e) {
      debugPrint('DownloadQueue: Error deleting offline file: $e');
    }
  }

  /// Clear the queue (cancel pending downloads)
  void clearQueue() {
    _queue.clear();
    notifyListeners();
  }
}
