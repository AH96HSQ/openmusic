import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents the context from which playback was initiated
enum PlaybackContext {
  song, // Individual song was clicked
  playlist, // Entire playlist was clicked
  album, // Entire album was clicked
  artist, // Entire artist was clicked
  search, // From search results
  recent, // Legacy - no longer used
  mostPlayed, // From most played songs
}

/// Simple persistent queue service. Holds a list of song IDs and exposes
/// reorder/remove/shuffle/repeat helpers. Persists to SharedPreferences.
class QueueService extends ChangeNotifier {
  QueueService._private();
  static final QueueService instance = QueueService._private();

  static const _queueKey = 'play_queue_v1';
  static const _originalQueueKey = 'play_queue_original_v1';
  static const _currentIndexKey = 'play_queue_index_v1';
  static const _shuffleKey = 'play_queue_shuffle_v1';
  static const _repeatKey = 'play_queue_repeat_v1';
  static const _playbackContextKey = 'play_queue_context_v1';

  List<String> _queue = [];
  List<String> _originalQueue = [];
  int _currentIndex = 0;
  bool _shuffle = false;
  int _repeatMode = 0; // 0 = off, 1 = all, 2 = one

  // Playback context tracking
  PlaybackContext _playbackContext = PlaybackContext.song;
  String?
  _playbackContextId; // ID of the playlist/album/artist that was clicked

  bool get shuffleEnabled => _shuffle;
  int get repeatMode => _repeatMode;
  List<String> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  String? get currentSongId =>
      _queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;

  // Playback context getters
  PlaybackContext get playbackContext => _playbackContext;
  String? get playbackContextId => _playbackContextId;

  /// Check if indicators should be shown for a specific playlist
  bool shouldShowPlaylistIndicator(String playlistId) {
    return _playbackContext == PlaybackContext.playlist &&
        _playbackContextId == playlistId;
  }

  /// Check if indicators should be shown for a specific album
  bool shouldShowAlbumIndicator(String albumId) {
    return _playbackContext == PlaybackContext.album &&
        _playbackContextId == albumId;
  }

  /// Check if indicators should be shown for a specific artist
  bool shouldShowArtistIndicator(String artistId) {
    return _playbackContext == PlaybackContext.artist &&
        _playbackContextId == artistId;
  }

  /// Check if indicators should be shown for most played songs
  bool shouldShowMostPlayedIndicator(String songId) {
    return _playbackContext == PlaybackContext.mostPlayed &&
        _playbackContextId == songId;
  }

  /// Check if there's a next song available considering repeat mode
  bool get hasNext {
    if (_queue.isEmpty || _queue.length <= 1) return false;

    // If repeat-one with multiple songs, behave like repeat-all
    if (_repeatMode == 2) return true;

    // If there are songs after current
    if (_currentIndex < _queue.length - 1) return true;

    // If at end but repeat-all is on, can go to beginning
    if (_repeatMode == 1) return true;

    return false;
  }

  /// Check if there's a previous song available (only checks queue position, not time)
  bool get hasPrevious {
    if (_queue.isEmpty || _queue.length <= 1) return false;

    // If repeat-one with multiple songs, behave like repeat-all
    if (_repeatMode == 2) return true;

    // If there are songs before current
    if (_currentIndex > 0) return true;

    // If at beginning but repeat-all is on, can go to end
    if (_repeatMode == 1) return true;

    return false;
  }

  Future<void> initialize() async {
    final sp = await SharedPreferences.getInstance();
    try {
      final raw = sp.getString(_queueKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _queue = decoded.map((e) => e.toString()).toList();
      }
      final origRaw = sp.getString(_originalQueueKey);
      if (origRaw != null && origRaw.isNotEmpty) {
        final decoded = jsonDecode(origRaw) as List<dynamic>;
        _originalQueue = decoded.map((e) => e.toString()).toList();
      } else {
        _originalQueue = List.from(_queue);
      }
      _currentIndex = sp.getInt(_currentIndexKey) ?? 0;
      _shuffle = sp.getBool(_shuffleKey) ?? false;
      // If a repeat mode was persisted, use it. Otherwise, leave as default (0)
      // The default may be adjusted based on loaded queue below.
      final persistedRepeat = sp.getInt(_repeatKey);
      if (persistedRepeat != null) {
        _repeatMode = persistedRepeat;
      }

      // Load playback context
      final contextRaw = sp.getString(_playbackContextKey);
      if (contextRaw != null && contextRaw.isNotEmpty) {
        try {
          final contextData = jsonDecode(contextRaw) as Map<String, dynamic>;
          final contextIndex = contextData['context'] as int? ?? 0;
          _playbackContext = PlaybackContext
              .values[contextIndex.clamp(0, PlaybackContext.values.length - 1)];
          _playbackContextId = contextData['contextId'] as String?;
        } catch (_) {
          _playbackContext = PlaybackContext.song;
          _playbackContextId = null;
        }
      }
    } catch (_) {
      // ignore
    }
    // If we loaded a queue and there's no persisted repeat setting, apply
    // the desired default: if the queue contains exactly one song, default
    // to repeat-one; otherwise default to repeat-all.
    final persistedRepeatCheck = await SharedPreferences.getInstance();
    final hasPersistedRepeat = persistedRepeatCheck.getInt(_repeatKey) != null;
    if (!hasPersistedRepeat) {
      if (_queue.length == 1) {
        _repeatMode = 2; // repeat one by default for single-song queue
      } else if (_queue.length > 1) {
        _repeatMode = 1; // repeat all for multi-song queues
      }
    }

    notifyListeners();
  }

  Future<void> setQueue(
    List<String> list, {
    int startIndex = 0,
    PlaybackContext context = PlaybackContext.song,
    String? contextId,
  }) async {
    _queue = List.from(list);
    _originalQueue = List.from(list);
    _currentIndex = startIndex.clamp(
      0,
      _queue.isNotEmpty ? _queue.length - 1 : 0,
    );
    _playbackContext = context;
    _playbackContextId = contextId;

    // Reset shuffle when queue is entirely replaced
    _shuffle = false;

    // Auto-set repeat mode based on queue size
    if (_queue.length == 1) {
      _repeatMode = 2; // repeat-one for single song
    } else if (_queue.length > 1) {
      _repeatMode = 1; // repeat-all for multiple songs
    } else {
      _repeatMode = 0; // no repeat for empty queue
    }

    await _persistAll();
    notifyListeners();
  }

  Future<void> addToQueue(String songId) async {
    _queue.add(songId);
    _originalQueue.add(songId);
    await _persistAll();
    notifyListeners();
  }

  /// Add song to play next (after current song)
  Future<void> playNext(String songId) async {
    final insertIndex = _currentIndex + 1;
    if (insertIndex <= _queue.length) {
      _queue.insert(insertIndex, songId);
      _originalQueue.insert(insertIndex, songId);
    } else {
      _queue.add(songId);
      _originalQueue.add(songId);
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _currentIndex;
    final removed = _queue.removeAt(index);

    // Remove from original queue at the same index to handle duplicates correctly
    // If shuffle is on, we need to find the corresponding item in original queue
    if (_shuffle) {
      // When shuffled, we need to track which song was removed
      // For now, just remove first occurrence (this maintains existing behavior)
      _originalQueue.remove(removed);
    } else {
      // When not shuffled, queues should be identical, so remove at same index
      if (index < _originalQueue.length) {
        _originalQueue.removeAt(index);
      }
    }

    if (removingCurrent) {
      if (_currentIndex >= _queue.length) _currentIndex = _queue.length - 1;
      if (_currentIndex < 0) _currentIndex = 0;
    } else if (index < _currentIndex) {
      _currentIndex = (_currentIndex - 1).clamp(
        0,
        _queue.isNotEmpty ? _queue.length - 1 : 0,
      );
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    // Keep original queue synced when shuffle is off
    if (!_shuffle) {
      _originalQueue = List.from(_queue);
    }
    // adjust current index
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex = (_currentIndex - 1).clamp(0, _queue.length - 1);
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex = (_currentIndex + 1).clamp(0, _queue.length - 1);
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    if (_shuffle) {
      // create randomized version with current song moved to top
      _originalQueue = List.from(_queue);
      final current = currentSongId;
      _queue.shuffle();

      // Move currently playing song to top of shuffled queue
      if (current != null) {
        final idx = _queue.indexOf(current);
        if (idx != -1 && idx != 0) {
          // Remove current song from its position and insert at top
          _queue.removeAt(idx);
          _queue.insert(0, current);
        }
        _currentIndex = 0; // Current song is now at top
      } else {
        _currentIndex = 0;
      }
    } else {
      // restore original order
      final current = currentSongId;
      _queue = List.from(_originalQueue);
      if (current != null) {
        final idx = _queue.indexOf(current);
        _currentIndex = idx == -1 ? 0 : idx;
      } else {
        _currentIndex = 0;
      }
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    _repeatMode = (_repeatMode + 1) % 3;
    await _persistAll();
    notifyListeners();
  }

  Future<void> moveToNext() async {
    if (_queue.isEmpty || _queue.length <= 1) return;

    final next = _currentIndex + 1;
    if (next >= _queue.length) {
      // If repeat-all or repeat-one with multiple songs, wrap to beginning
      if (_repeatMode == 1 || _repeatMode == 2) {
        _currentIndex = 0;
      } else {
        // end of queue
        return;
      }
    } else {
      _currentIndex = next;
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> moveToPrevious() async {
    if (_queue.isEmpty || _queue.length <= 1) return;

    final prev = _currentIndex - 1;
    if (prev < 0) {
      // If repeat-all or repeat-one with multiple songs, wrap to end
      if (_repeatMode == 1 || _repeatMode == 2) {
        _currentIndex = _queue.length - 1;
      } else {
        // start of queue
        return;
      }
    } else {
      _currentIndex = prev;
    }
    await _persistAll();
    notifyListeners();
  }

  Future<void> moveToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _persistAll();
    notifyListeners();
  }

  Future<void> _persistAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_queueKey, jsonEncode(_queue));
      await sp.setString(_originalQueueKey, jsonEncode(_originalQueue));
      await sp.setInt(_currentIndexKey, _currentIndex);
      await sp.setBool(_shuffleKey, _shuffle);
      await sp.setInt(_repeatKey, _repeatMode);

      // Persist playback context
      final contextData = {
        'context': _playbackContext.index,
        'contextId': _playbackContextId,
      };
      await sp.setString(_playbackContextKey, jsonEncode(contextData));
    } catch (_) {}
  }
}
