import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';
import 'queue_service.dart';
import 'simple_playback_controller.dart';

/// Audio handler that integrates OpenMusic with OS media notifications & controls.
class OpenMusicAudioHandler extends BaseAudioHandler {
  final _pc = SimplePlaybackController.instance;
  final _queue = QueueService.instance;

  OpenMusicAudioHandler() {
    debugPrint('AudioHandler: constructor');
    // Keep notification in sync with player + queue
    _pc.addListener(_refreshMediaItem);
    _pc.playerStateStream.listen(_onPlayerState);
    _pc.positionStream.listen(_onPosition);
    _queue.addListener(_refreshQueue);
    // Defer any plugin calls to after init returns to avoid blocking init
    scheduleMicrotask(() {
      debugPrint('AudioHandler: post-init microtask running');
      _pushInitialSnapshot();
      _refreshMediaItem();
      _refreshQueue();
    });
  }

  void _pushInitialSnapshot() {
    try {
      final playing = _pc.isPlaying;
      final state = PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: playing
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: playing,
        updatePosition: _pc.currentPosition,
        speed: 1.0,
      );
      playbackState.add(state);
      // Also hook future updates
      _pc.playerStateStream.first.then(_onPlayerState);
      _onPosition(_pc.currentPosition);
    } catch (_) {}
  }

  Future<Uri?> _resolveArtUri(Map<String, Object?> row, String id) async {
    // Prefer local cached artwork file if present
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'artwork', '${id}_artwork.jpg'));
      if (await file.exists()) {
        return Uri.file(file.path);
      }
    } catch (_) {}

    // Fallback to a remote artwork URL
    final largest = row['artwork_largest'] as String?;
    if (largest != null && largest.isNotEmpty) {
      return Uri.tryParse(largest);
    }

    // Try parse from images JSON (if stored)
    final imagesJson = row['artwork_images'] as String?;
    if (imagesJson != null && imagesJson.isNotEmpty) {
      try {
        final images = (jsonDecode(imagesJson) as List?) ?? const [];
        if (images.isNotEmpty) {
          final url = images.first['url'] as String?;
          if (url != null && url.isNotEmpty) return Uri.tryParse(url);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _refreshMediaItem() async {
    final id = _pc.currentSongId ?? _queue.currentSongId;
    if (id == null || id.isEmpty) {
      mediaItem.add(null);
      debugPrint('AudioHandler: mediaItem cleared (no current song)');
      return;
    }
    // Immediately publish a minimal item to allow the service to show a notification
    if (mediaItem.valueOrNull?.id != id) {
      final bootstrap = MediaItem(id: id, title: 'Unknown Title', artist: '');
      mediaItem.add(bootstrap);
      debugPrint('AudioHandler: mediaItem bootstrap -> $id');
    }
    try {
      final row = await DatabaseHelper.instance.getSong(id);
      if (row == null) return;
      final art = await _resolveArtUri(Map<String, Object?>.from(row), id);
      final item = MediaItem(
        id: id,
        title: (row['title'] as String?) ?? 'Unknown Title',
        artist: (row['artists'] as String?) ?? 'Unknown Artist',
        album: (row['album'] as String?) ?? '',
        duration: row['duration_ms'] is int
            ? Duration(milliseconds: row['duration_ms'] as int)
            : null,
        artUri: art,
      );
      mediaItem.add(item);
      debugPrint('AudioHandler: mediaItem set -> ${item.title}');
    } catch (e) {
      debugPrint('AudioHandler: error loading media item: $e');
    }
  }

  void _onPlayerState(PlayerState s) {
    debugPrint(
      'AudioHandler: onPlayerState playing=${s.playing} state=${s.processingState}',
    );
    final playing = s.playing;
    final processing = s.processingState;
    final state = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: switch (processing) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading ||
        ProcessingState.buffering => AudioProcessingState.loading,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _pc.currentPosition,
      speed: 1.0,
    );
    playbackState.add(state);
  }

  // Throttle position updates to system notification (every 1 second)
  Duration? _lastReportedPosition;

  void _onPosition(Duration pos) {
    // Only update if position changed by at least 1 second
    // This reduces system notification overhead
    if (_lastReportedPosition == null ||
        (pos - _lastReportedPosition!).inSeconds.abs() >= 1) {
      _lastReportedPosition = pos;
      final s = playbackState.value;
      playbackState.add(s.copyWith(updatePosition: pos));
    }
  }

  Future<void> _refreshQueue() async {
    final ids = _queue.queue;
    final items = <MediaItem>[];
    for (final id in ids) {
      try {
        final row = await DatabaseHelper.instance.getSong(id);
        if (row == null) continue;
        final art = await _resolveArtUri(Map<String, Object?>.from(row), id);
        items.add(
          MediaItem(
            id: id,
            title: (row['title'] as String?) ?? 'Unknown Title',
            artist: (row['artists'] as String?) ?? 'Unknown Artist',
            album: (row['album'] as String?) ?? '',
            duration: row['duration_ms'] is int
                ? Duration(milliseconds: row['duration_ms'] as int)
                : null,
            artUri: art,
          ),
        );
      } catch (_) {}
    }
    queue.add(items);
    debugPrint('AudioHandler: queue updated (${items.length} items)');
  }

  // System action handlers
  @override
  Future<void> play() async {
    final id = _pc.currentSongId ?? _queue.currentSongId;
    if (id != null) {
      await _pc.play(id, null);
    } else {
      await _pc.resume();
    }
  }

  @override
  Future<void> pause() => _pc.pause();

  @override
  Future<void> stop() => _pc.stop();

  @override
  Future<void> skipToNext() async {
    if (_queue.hasNext) {
      await _queue.moveToNext();
      final id = _queue.currentSongId;
      if (id != null) await _pc.play(id, null);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_pc.currentPosition.inSeconds > 7) {
      await _pc.seek(Duration.zero);
    } else if (_queue.hasPrevious) {
      await _queue.moveToPrevious();
      final id = _queue.currentSongId;
      if (id != null) await _pc.play(id, null);
    }
  }

  @override
  Future<void> seek(Duration position) => _pc.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    await _queue.moveToIndex(index);
    final id = _queue.currentSongId;
    if (id != null) await _pc.play(id, null);
  }
}

OpenMusicAudioHandler? _audioHandler;

Future<OpenMusicAudioHandler> initAudioService() async {
  if (_audioHandler != null) return _audioHandler!;
  debugPrint('AudioHandler: Initializing AudioService...');
  Timer? warn;
  try {
    warn = Timer(const Duration(seconds: 5), () {
      debugPrint(
        'AudioHandler: AudioService.init is taking longer than expected...',
      );
    });
    _audioHandler = await AudioService.init(
      builder: () => OpenMusicAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.openmusic.app.channel.audio',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidStopForegroundOnPause: false,
        androidNotificationChannelDescription: 'Playback controls and metadata',
      ),
    );
    debugPrint('AudioHandler: AudioService initialized');
  } catch (e, st) {
    debugPrint('AudioHandler: AudioService.init threw: $e');
    debugPrint('$st');
    rethrow;
  } finally {
    warn?.cancel();
  }
  return _audioHandler!;
}

OpenMusicAudioHandler? getAudioHandler() => _audioHandler;
