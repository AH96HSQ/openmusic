import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'queue_service.dart';
import 'package:http/http.dart' as http;
import '../data/database_helper.dart';
import 'status_message_controller.dart';
import 'download_helper.dart';
import '../helpers/most_played_helper.dart';
import '../ui/widgets/recent_wheel.dart';
import 'package:uuid/uuid.dart';
import 'spotify_client.dart';
import 'download_queue_service.dart';

enum PlaybackMode { stopped, loading, streaming, file, error }

/// Throttle extension for streams - reduces update frequency
extension ThrottleExtension<T> on Stream<T> {
  Stream<T> throttle(Duration duration) {
    Timer? timer;
    T? lastValue;
    bool hasValue = false;

    return transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) {
          lastValue = data;
          hasValue = true;

          if (timer == null || !timer!.isActive) {
            sink.add(data);
            timer = Timer(duration, () {
              if (hasValue) {
                sink.add(lastValue as T);
                hasValue = false;
              }
            });
          }
        },
        handleDone: (sink) {
          timer?.cancel();
          sink.close();
        },
      ),
    );
  }
}

/// Simplified playback controller based on working old project approach
class SimplePlaybackController extends ChangeNotifier {
  SimplePlaybackController._internal() {
    _player = AudioPlayer();
    _setupPlayerErrorHandler();
  }

  void _setupPlayerErrorHandler() {
    _player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: (e, s) {
        final errorMessage = e.toString().toLowerCase();
        debugPrint('AudioPlayer error: $e');
        debugPrint('AudioPlayer error stack: $s');

        // Check for specific AudioTrack errors that cause restart loops
        final isAudioTrackError =
            errorMessage.contains('audiotrack') ||
            errorMessage.contains('write failed') ||
            errorMessage.contains('audio sink') ||
            errorMessage.contains('renderer error');

        if (isAudioTrackError) {
          debugPrint(
            'SimplePlaybackController: Detected AudioTrack-related error, entering immediate cooldown',
          );
          _consecutiveErrors =
              _maxConsecutiveErrors; // Force immediate cooldown
        } else {
          _consecutiveErrors++;
        }

        debugPrint(
          'SimplePlaybackController: Consecutive errors: $_consecutiveErrors (AudioTrack error: $isAudioTrackError)',
        );

        // If too many consecutive errors, stop trying to prevent loops
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          debugPrint(
            'SimplePlaybackController: Too many consecutive errors, stopping playback and entering cooldown',
          );
          _stopPlayTimeTracking(); // Stop tracking on error
          _mode = PlaybackMode.stopped;
          _consecutiveErrors = 0; // Reset counter
          _enterErrorCooldown();
          _persistMode();
          notifyListeners();

          // For AudioTrack errors, also try to stop the player completely and mark system as failed
          if (isAudioTrackError) {
            _markAudioSystemFailed();
            Timer.run(() async {
              try {
                await _player.stop();
                await _player.dispose();
                _player = AudioPlayer();
                // Re-setup the error handler for the new player
                _setupPlayerErrorHandler();
              } catch (disposeError) {
                debugPrint(
                  'Error disposing/recreating AudioPlayer: $disposeError',
                );
              }
            });
          }
        }
      },
    );
  }

  Future<void> _handlePlaybackCompleted() async {
    // If we're in error cooldown, don't handle completion to prevent loops
    if (_isInErrorCooldown()) {
      debugPrint(
        'SimplePlaybackController: Skipping completion handling during error cooldown',
      );
      return;
    }

    // Handle end-of-track behavior based on queue repeat mode
    try {
      final qs = QueueService.instance;
      // If repeat-one, restart the same song
      if (qs.repeatMode == 2) {
        try {
          await _player.seek(Duration.zero);
          await _player.play();

          if (!_player.playing &&
              _currentSongId != null &&
              _currentSongId!.isNotEmpty &&
              _consecutiveErrors < _maxConsecutiveErrors &&
              !_isInErrorCooldown()) {
            // Ensure player is stopped/clean before reloading the same track
            try {
              await _player.stop();
            } catch (_) {}
            await play(_currentSongId!, null);
          }

          await _persistMode();
          notifyListeners();
          return;
        } catch (e) {
          debugPrint('Error restarting track for repeat-one: $e');
          _consecutiveErrors++;
          if (_consecutiveErrors >= _maxConsecutiveErrors) {
            _enterErrorCooldown();
          }
        }
      }

      // Not repeat-one: try to advance the queue
      final prevId = qs.currentSongId;
      await qs.moveToNext();
      final nextId = qs.currentSongId;
      if (nextId != null &&
          nextId.isNotEmpty &&
          nextId != prevId &&
          _consecutiveErrors < _maxConsecutiveErrors &&
          !_isInErrorCooldown()) {
        // Ensure player is stopped before starting next track to avoid
        // playing/completed-state conflicts
        try {
          await _player.stop();
        } catch (_) {}
        await play(nextId, null);
        return;
      }
    } catch (e) {
      debugPrint('Error advancing queue after completion: $e');
    }

    _stopPlayTimeTracking(); // Stop tracking play time when playback completes
    _mode = PlaybackMode.stopped;
    await _persistMode();
    notifyListeners();
  }

  static final SimplePlaybackController instance =
      SimplePlaybackController._internal();

  static const _kModeKey = 'playback.mode';
  static const _kCurrentSongKey = 'playback.current_song_id';

  late final AudioPlayer _player;
  bool _isInitialized = false;

  PlaybackMode _mode = PlaybackMode.stopped;
  PlaybackMode get mode => _mode;

  String? _lastErrorSongId; // Track which song had the error
  String? get lastErrorSongId => _lastErrorSongId;

  String? _currentSongId;
  String? get currentSongId => _currentSongId;

  String? _currentStreamUrl; // Track the current streaming URL

  // Debounce mechanism to prevent restart loops
  DateTime? _lastPlayRequest;
  static const _playDebounceMs = 1000; // 1 second debounce

  // Error tracking to prevent excessive retries
  int _consecutiveErrors = 0;
  static const _maxConsecutiveErrors = 3;

  // Error cooldown mechanism to prevent rapid retry loops
  DateTime? _lastErrorTime;
  static const _errorCooldownMs =
      5000; // 5 second cooldown after consecutive errors
  bool _inErrorCooldown = false;

  // Audio system failure protection
  bool _audioSystemFailed = false;
  DateTime? _audioSystemFailureTime;
  static const _audioSystemRecoveryMs = 10000; // 10 second recovery time

  // Request ID system for backend cancellation
  String? _activeRequestId; // Current active request ID
  static const _uuid = Uuid();

  // Multi-request cancellation system (kept for local operations)
  Completer<String?>? _currentPlayOperation;
  String? _currentPlayOperationSongId;

  // Active connections tracking for cleanup (simplified - mainly for local cleanup)
  // Track which songId owns each resource to prevent cross-operation interference
  StreamSubscription? _activeSSESubscription;
  String? _activeSSESongId;
  http.Client? _activeHttpClient;
  String? _activeHttpClientSongId;
  Completer<void>? _activeDownloadCompleter;
  String? _activeDownloadCompleterSongId;

  // Play time tracking (event-based - no timer needed)
  DateTime? _playStartTime;
  String? _playTimeSongId; // Track which song we're timing

  // Debounced notify mechanism to batch state changes
  Timer? _notifyDebouncer;
  bool _notifyPending = false;

  // Audio interruption handling
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSubscription;

  // Next song preloading for smoother transitions
  String? _preloadedNextSongId;
  String? _preloadedNextSongPath;
  bool _isPreloading = false;

  bool get isPlaying => _player.playing;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Throttled position stream - updates every 500ms instead of 200ms
  /// Reduces UI rebuilds from 5/sec to 2/sec for better performance
  Stream<Duration> get positionStream =>
      _player.positionStream.throttle(const Duration(milliseconds: 500));

  Stream<Duration?> get durationStream => _player.durationStream;

  Duration get currentPosition => _player.position;
  Duration? get currentDuration => _player.duration;

  /// Enter error cooldown to prevent rapid restart loops
  void _enterErrorCooldown() {
    _lastErrorTime = DateTime.now();
    _inErrorCooldown = true;

    // Clear cooldown after timeout
    Timer(Duration(milliseconds: _errorCooldownMs), () {
      _inErrorCooldown = false;
      debugPrint('SimplePlaybackController: Error cooldown ended');
    });
  }

  /// Check if we're in error cooldown period
  bool _isInErrorCooldown() {
    if (!_inErrorCooldown || _lastErrorTime == null) return false;

    final elapsed = DateTime.now().difference(_lastErrorTime!).inMilliseconds;
    return elapsed < _errorCooldownMs;
  }

  /// Mark audio system as failed to prevent further operations
  void _markAudioSystemFailed() {
    _audioSystemFailed = true;
    _audioSystemFailureTime = DateTime.now();
    debugPrint(
      'SimplePlaybackController: Audio system marked as failed, entering recovery mode',
    );

    // Auto-recovery after timeout
    Timer(Duration(milliseconds: _audioSystemRecoveryMs), () {
      _audioSystemFailed = false;
      debugPrint('SimplePlaybackController: Audio system recovery completed');
    });
  }

  /// Check if audio system has failed and needs recovery
  bool _isAudioSystemFailed() {
    if (!_audioSystemFailed || _audioSystemFailureTime == null) return false;

    final elapsed = DateTime.now()
        .difference(_audioSystemFailureTime!)
        .inMilliseconds;
    if (elapsed >= _audioSystemRecoveryMs) {
      _audioSystemFailed = false;
      return false;
    }
    return true;
  }

  /// Cancel any currently running play operation
  /// Note: Does NOT complete the completer - the old operation's finally block
  /// will handle cleanup using ownership checks.
  void _cancelCurrentOperation(String newSongId) {
    if (_currentPlayOperationSongId != null) {
      debugPrint(
        'SimplePlaybackController: Marking operation for $_currentPlayOperationSongId as cancelled (new request: $newSongId) - will be cleaned by its finally block',
      );
      // Don't complete the completer here - let the old operation's finally block handle it
      // with proper ownership checks. We just clear the tracking variables.
      _currentPlayOperation = null;
      _currentPlayOperationSongId = null;
    }
  }

  /// Check if current operation was cancelled
  bool _isOperationCancelled(String songId) {
    // Only consider cancelled if this specific operation was cancelled
    // Don't use the global _operationCancelled flag as it can affect new operations
    return _currentPlayOperationSongId != songId;
  }

  /// Cancel the active backend request using request ID (fire and forget)
  void _cancelBackendRequest() {
    if (_activeRequestId != null) {
      final requestIdToCancel = _activeRequestId;
      debugPrint(
        'Robust Playback: 🛑 Cancelling operation (local only): $requestIdToCancel',
      );

      // Just clear the request ID - no backend to notify since we use on-device downloads
      _activeRequestId = null;
    }
  }

  /// Cancel all active connections and operations from previous songs
  /// Only cancels resources that don't belong to the current operation
  void _cancelActiveConnections() {
    final currentSong = _currentPlayOperationSongId;
    debugPrint(
      'Robust Playback: 🛑 Cancelling connections from previous song (protecting: $currentSong)',
    );

    // Cancel backend request (fire-and-forget, non-blocking)
    _cancelBackendRequest();

    // Hide any status messages from previous song
    StatusMessageController.instance.hide();

    // Clean up local connections - only if they belong to a different operation
    if (_activeSSESubscription != null) {
      if (_activeSSESongId != currentSong || currentSong == null) {
        _activeSSESubscription!.cancel(); // Don't await
        _activeSSESubscription = null;
        _activeSSESongId = null;
        debugPrint(
          'Robust Playback: ✓ Cancelled SSE subscription (songId: $_activeSSESongId)',
        );
      } else {
        debugPrint(
          'Robust Playback: ⚠ Skipping SSE cancel - belongs to current operation',
        );
      }
    }

    if (_activeHttpClient != null) {
      if (_activeHttpClientSongId != currentSong || currentSong == null) {
        _activeHttpClient!.close();
        _activeHttpClient = null;
        _activeHttpClientSongId = null;
        debugPrint(
          'Robust Playback: ✓ Closed HTTP client (songId: $_activeHttpClientSongId)',
        );
      } else {
        debugPrint(
          'Robust Playback: ⚠ Skipping HTTP client close - belongs to current operation',
        );
      }
    }

    // Complete any pending download operations from previous songs
    if (_activeDownloadCompleter != null &&
        !_activeDownloadCompleter!.isCompleted) {
      if (_activeDownloadCompleterSongId != currentSong ||
          currentSong == null) {
        _activeDownloadCompleter!.complete();
        _activeDownloadCompleter = null;
        _activeDownloadCompleterSongId = null;
        debugPrint(
          'Robust Playback: ✓ Completed download completer (songId: $_activeDownloadCompleterSongId)',
        );
      } else {
        debugPrint(
          'Robust Playback: ⚠ Skipping download completer - belongs to current operation',
        );
      }
    }

    debugPrint(
      'Robust Playback: ✓ All old connections cancelled (non-blocking)',
    );
  }

  /// Static method for download helper to check playback status
  static Map<String, dynamic> getCurrentPlaybackStatus() {
    final controller = SimplePlaybackController.instance;
    return {
      'currentSongId': controller.currentSongId,
      'mode': controller._toString(controller.mode),
      'isPlaying': controller.isPlaying,
    };
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getString(_kModeKey) ?? 'stopped';
      _mode = _fromString(m);

      // If we were in loading state when app closed, reset to stopped
      // (no active operation to resume)
      if (_mode == PlaybackMode.loading) {
        debugPrint(
          'SimplePlaybackController: Resetting loading mode to stopped on app start',
        );
        _mode = PlaybackMode.stopped;
        await _persistMode();
      }

      _currentSongId = prefs.getString(_kCurrentSongKey);
    } catch (_) {}
  }

  /// Initialize audio session for proper playback on first launch
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    // Skip audio session configuration on Windows as audio_session doesn't support it
    if (Platform.isWindows) {
      debugPrint(
        'SimplePlaybackController: Skipping audio session on Windows (not supported)',
      );
      await _player.setVolume(1.0);
      _isInitialized = true;
      return;
    }

    try {
      debugPrint('SimplePlaybackController: Initializing audio session...');
      final session = await AudioSession.instance;

      // Configure with specific settings for music playback
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );

      // Handle audio focus interruptions (phone calls, other apps, etc.)
      _interruptionSubscription?.cancel();
      _interruptionSubscription = session.interruptionEventStream.listen((
        event,
      ) {
        debugPrint(
          'SimplePlaybackController: Audio interruption - begin=${event.begin}, type=${event.type}',
        );
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // Lower volume temporarily
              _player.setVolume(0.3);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // Pause playback
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // Restore volume
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              // Don't auto-resume after call - let user decide
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // Handle audio device changes (headphones unplugged, etc.)
      _devicesChangedSubscription?.cancel();
      _devicesChangedSubscription = session.devicesChangedEventStream.listen((
        event,
      ) {
        debugPrint(
          'SimplePlaybackController: Audio devices changed - added=${event.devicesAdded.length}, removed=${event.devicesRemoved.length}',
        );
        // If headphones are unplugged while playing, pause
        if (event.devicesRemoved.isNotEmpty && _player.playing) {
          final removedHeadphones = event.devicesRemoved.any(
            (d) =>
                d.type == AudioDeviceType.wiredHeadset ||
                d.type == AudioDeviceType.wiredHeadphones ||
                d.type == AudioDeviceType.bluetoothA2dp ||
                d.type == AudioDeviceType.bluetoothLe,
          );
          if (removedHeadphones) {
            debugPrint(
              'SimplePlaybackController: Headphones unplugged, pausing playback',
            );
            pause();
          }
        }
      });

      await session.setActive(true);
      await _player.setVolume(1.0);
      _isInitialized = true;

      debugPrint(
        'SimplePlaybackController: Audio session initialized with interruption handling',
      );
    } catch (e) {
      debugPrint(
        'SimplePlaybackController: Failed to initialize audio session: $e',
      );
      _isInitialized = true; // Continue anyway
    }
  }

  PlaybackMode _fromString(String s) {
    switch (s) {
      case 'loading':
        return PlaybackMode.loading;
      case 'streaming':
        return PlaybackMode.streaming;
      case 'file':
        return PlaybackMode.file;
      default:
        return PlaybackMode.stopped;
    }
  }

  String _toString(PlaybackMode m) => m.toString().split('.').last;

  Future<void> _persistMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kModeKey, _toString(_mode));
      if (_currentSongId != null) {
        await prefs.setString(_kCurrentSongKey, _currentSongId!);
      }
    } catch (_) {}
  }

  /// Debounced notify to batch rapid state changes
  void _debouncedNotify() {
    _notifyPending = true;
    _notifyDebouncer?.cancel();
    _notifyDebouncer = Timer(const Duration(milliseconds: 50), () {
      if (_notifyPending) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  void _onPlaybackEvent(PlaybackEvent ev) async {
    debugPrint(
      'SimplePlaybackController: PlaybackEvent - state: ${ev.processingState}, playing: ${_player.playing}',
    );

    // If we're in error cooldown, ignore all playback events to prevent loops
    if (_isInErrorCooldown()) {
      debugPrint(
        'SimplePlaybackController: Ignoring playback event during error cooldown',
      );
      return;
    }

    if (ev.processingState == ProcessingState.completed) {
      // Defer completion handling to avoid controlling the player while the
      // playbackEventStream is firing (avoids 'Cannot fire new event')
      Timer.run(() {
        _handlePlaybackCompleted();
      });
      return;
    } else if (ev.processingState == ProcessingState.buffering) {
      // Keep in loading mode while buffering
      if (_mode != PlaybackMode.loading) {
        _mode = PlaybackMode.loading;
        await _persistMode();
        _debouncedNotify(); // Use debounced notify
      }
    } else if (ev.processingState == ProcessingState.ready && _player.playing) {
      // Player is ready and actually playing - reset error counter
      _consecutiveErrors = 0;
      debugPrint(
        'SimplePlaybackController: Ready and playing - current mode: $_mode',
      );

      // Start tracking play time for this song
      if (_currentSongId != null) {
        _startPlayTimeTracking();
      }

      // Check if we should preload next song (for smoother transitions)
      _checkAndPreloadNextSong();

      if (_mode == PlaybackMode.loading) {
        // We were loading, now we need to determine if we're streaming or file
        // Check if we have a tracked streaming URL
        if (_currentStreamUrl != null &&
            (_currentStreamUrl!.contains('http://') ||
                _currentStreamUrl!.contains('https://'))) {
          debugPrint(
            'SimplePlaybackController: Setting mode to streaming (using tracked URL: $_currentStreamUrl)',
          );
          _mode = PlaybackMode.streaming;

          // Only do streaming-related tasks for actual streaming
          if (_currentSongId != null) {
            // Update server file availability since streaming started successfully
            _updateServerFileStatusForSong(_currentSongId!);

            // Start downloading the file for offline use
            DownloadHelper.instance.downloadSong(_currentSongId!);
          }
        } else {
          debugPrint(
            'SimplePlaybackController: Setting mode to file (no streaming URL tracked)',
          );
          _mode = PlaybackMode.file;
        }

        await _persistMode();
        _debouncedNotify(); // Use debounced notify
      } else if (_mode == PlaybackMode.file) {
        debugPrint(
          'SimplePlaybackController: Actually started playing from local file',
        );
        // Don't notify - mode hasn't changed, just continuing playback
      } else if (_mode == PlaybackMode.streaming) {
        debugPrint('SimplePlaybackController: Continuing streaming playback');

        // Ensure server file availability is marked in database
        if (_currentSongId != null) {
          _updateServerFileStatusForSong(_currentSongId!);
        }
        // Don't notify - mode hasn't changed, just continuing playback
      }
      // Removed duplicate notifyListeners() that was causing infinite loop
    } else {
      // For any other state changes (like pause/stop), notify only if needed
      // This prevents excessive notifications during normal playback
    }
  }

  /// Main play method - simplified approach
  Future<String?> play(String songId, Map<String, dynamic>? raw) async {
    debugPrint('Robust Playback: ========== PLAY REQUEST STARTED ==========');
    debugPrint('Robust Playback: songId: $songId');
    debugPrint('Robust Playback: raw data provided: ${raw != null}');
    debugPrint(
      'Robust Playback: Current state - mode: $_mode, currentSongId: $_currentSongId',
    );

    await _ensureInitialized();

    // Check if we're in error cooldown period or audio system has failed
    if (_isInErrorCooldown()) {
      debugPrint('Robust Playback: ❌ BLOCKED - In error cooldown for $songId');
      return 'System in error cooldown, please wait';
    }

    if (_isAudioSystemFailed()) {
      debugPrint(
        'Robust Playback: ❌ BLOCKED - Audio system failed for $songId',
      );
      return 'Audio system failed, recovery in progress';
    }

    // Cancel any previous operation before starting new one
    _cancelCurrentOperation(songId);

    // Set up cancellation for this operation AFTER cancelling previous
    _currentPlayOperation = Completer<String?>();
    _currentPlayOperationSongId = songId;

    // Debounce rapid play requests to prevent restart loops
    final now = DateTime.now();
    if (_lastPlayRequest != null &&
        now.difference(_lastPlayRequest!).inMilliseconds < _playDebounceMs) {
      debugPrint(
        'SimplePlaybackController: Ignoring rapid play request for $songId (debounced)',
      );
      return null;
    }
    _lastPlayRequest = now;

    // Check if we're already playing this exact song - if so, just resume if paused
    debugPrint('Robust Playback: Checking if song is already playing...');
    debugPrint(
      'Robust Playback: - Player processing state: ${_player.processingState}',
    );
    debugPrint('Robust Playback: - Player playing: ${_player.playing}');

    if (_currentSongId == songId &&
        (_mode == PlaybackMode.streaming || _mode == PlaybackMode.file) &&
        _player.processingState != ProcessingState.idle) {
      debugPrint('Robust Playback: ✓ Song $songId is already loaded');
      if (!_player.playing) {
        debugPrint('Robust Playback: ▶ Resuming paused song $songId');
        await _player.play();
        _resumePlayTimeTracking(); // Resume time tracking
        notifyListeners(); // Notify UI that playback resumed
      } else {
        debugPrint(
          'Robust Playback: ✓ Song $songId already playing, no action needed',
        );
      }

      // Complete the operation successfully
      if (_currentPlayOperation != null &&
          !_currentPlayOperation!.isCompleted) {
        _currentPlayOperation!.complete(null);
      }
      _currentPlayOperation = null;

      // Only clear songId if this operation is still the current one
      if (_currentPlayOperationSongId == songId) {
        _currentPlayOperationSongId = null;
      }

      return null; // Success - no error
    }

    // If we reach here, either it's a different song or AudioPlayer is in idle state
    // (which happens after app restart even if mode was restored)
    if (_currentSongId == songId &&
        _player.processingState == ProcessingState.idle) {
      debugPrint(
        'Robust Playback: ⚠ Same song but AudioPlayer is idle - will reload audio source',
      );
    }

    debugPrint('Robust Playback: 🎵 Starting NEW playback for song $songId');

    // Hide any existing status message immediately when starting new playback
    StatusMessageController.instance.hide();

    // Only cancel backend requests if we were downloading/streaming
    // Skip if playing from local file (no active download to cancel)
    if (_mode == PlaybackMode.loading || _mode == PlaybackMode.streaming) {
      debugPrint(
        'Robust Playback: Previous mode was $_mode - cancelling backend operations',
      );
      _cancelActiveConnections();
    } else {
      debugPrint(
        'Robust Playback: Previous mode was $_mode - no backend operations to cancel',
      );
    }

    // Start the actual play operation with cancellation support
    return _performPlayOperation(songId, raw);
  }

  /// Perform the actual play operation with cancellation checks
  Future<String?> _performPlayOperation(
    String songId,
    Map<String, dynamic>? raw,
  ) async {
    // Store reference to this operation's completer to check for cancellation
    final operationCompleter = _currentPlayOperation;

    try {
      // Check if cancelled before starting
      if (_isOperationCancelled(songId) ||
          operationCompleter?.isCompleted == true) {
        if (operationCompleter?.isCompleted == true) {
          final result = await operationCompleter!.future;
          // Only treat as cancellation if result is not null (null means successful completion)
          if (result != null) {
            debugPrint(
              'SimplePlaybackController: Operation cancelled via Completer before starting for $songId: $result',
            );
            return result;
          }
          // If result is null, it means successful completion, so continue
        } else {
          debugPrint(
            'SimplePlaybackController: Operation cancelled before starting for $songId',
          );
          return 'Operation cancelled';
        }
      }

      // Immediately stop any current audio to prevent overlap
      debugPrint('Robust Playback: Stopping previous audio...');
      try {
        await _player.stop();
        debugPrint('Robust Playback: ✓ Successfully stopped previous audio');
      } catch (e) {
        debugPrint('Robust Playback: ⚠ Error stopping previous audio: $e');
      }

      // Check if cancelled after stopping
      if (_isOperationCancelled(songId) ||
          operationCompleter?.isCompleted == true) {
        if (operationCompleter?.isCompleted == true) {
          final result = await operationCompleter!.future;
          // Only treat as cancellation if result is not null (null means successful completion)
          if (result != null) {
            debugPrint(
              'SimplePlaybackController: Operation cancelled via Completer after stopping previous audio for $songId: $result',
            );
            return result;
          }
          // If result is null, it means successful completion, so continue
        } else {
          debugPrint(
            'SimplePlaybackController: Operation cancelled after stopping previous audio for $songId',
          );
          return 'Operation cancelled';
        }
      }

      _currentSongId = songId;
      _mode = PlaybackMode.loading;
      _lastErrorSongId = null; // Clear error state when starting new song

      // Clear preload cache since we're switching songs
      if (_preloadedNextSongId != songId) {
        _preloadedNextSongId = null;
        _preloadedNextSongPath = null;
      }

      debugPrint('Robust Playback: ⏳ Mode set to LOADING');
      await _persistMode();
      notifyListeners();

      // Check if cancelled before database lookup
      if (_isOperationCancelled(songId) ||
          operationCompleter?.isCompleted == true) {
        if (operationCompleter?.isCompleted == true) {
          final result = await operationCompleter!.future;
          // Only treat as cancellation if result is not null (null means successful completion)
          if (result != null) {
            debugPrint(
              'Robust Playback: ❌ Operation cancelled via Completer before database lookup for $songId: $result',
            );
            return result;
          }
          // If result is null, it means successful completion, so continue
        } else {
          debugPrint(
            'Robust Playback: ❌ Operation cancelled before database lookup for $songId',
          );
          return 'Operation cancelled';
        }
      }

      // Try to get file info from database first
      debugPrint('Robust Playback: 🔍 Looking up song in database...');
      final row = await DatabaseHelper.instance.getSong(songId);
      debugPrint(
        'Robust Playback: Database lookup ${row != null ? "✓ FOUND" : "❌ NOT FOUND"}',
      );

      // Check if this is a device file - handle it differently
      if (row != null) {
        final isDeviceFile = (row['is_device_file'] as String?) == 'true';
        final localPath = row['on_device_filename'] as String?;
        final onDeviceStatus = row['on_device_status'] as String?;

        debugPrint('Robust Playback: Song metadata:');
        debugPrint('Robust Playback: - isDeviceFile: $isDeviceFile');
        debugPrint('Robust Playback: - localPath: $localPath');
        debugPrint('Robust Playback: - onDeviceStatus: $onDeviceStatus');

        // For device files, always try local file first and don't contact server
        if (isDeviceFile && localPath != null && localPath.isNotEmpty) {
          debugPrint('Robust Playback: 📁 Attempting to play DEVICE FILE');
          // Check if cancelled before checking file existence
          if (_isOperationCancelled(songId) ||
              operationCompleter?.isCompleted == true) {
            if (operationCompleter?.isCompleted == true) {
              final result = await operationCompleter!.future;
              // Only treat as cancellation if result is not null (null means successful completion)
              if (result != null) {
                debugPrint(
                  'SimplePlaybackController: Operation cancelled via Completer before device file check for $songId: $result',
                );
                return result;
              }
              // If result is null, it means successful completion, so continue
            } else {
              debugPrint(
                'SimplePlaybackController: Operation cancelled before device file check for $songId',
              );
              return 'Operation cancelled';
            }
          }

          debugPrint(
            'Robust Playback: Checking if device file exists at: $localPath',
          );
          final file = File(localPath);
          if (await file.exists()) {
            debugPrint('Robust Playback: ✓ Device file EXISTS at: $localPath');

            // Check if cancelled before playing device file
            if (_isOperationCancelled(songId) ||
                operationCompleter?.isCompleted == true) {
              if (operationCompleter?.isCompleted == true) {
                final result = await operationCompleter!.future;
                // Only treat as cancellation if result is not null (null means successful completion)
                if (result != null) {
                  debugPrint(
                    'Robust Playback: ❌ Operation cancelled via Completer before playing device file for $songId: $result',
                  );
                  return result;
                }
                // If result is null, it means successful completion, so continue
              } else {
                debugPrint(
                  'Robust Playback: ❌ Operation cancelled before playing device file for $songId',
                );
                return 'Operation cancelled';
              }
            }

            // Play from device file directly
            debugPrint(
              'Robust Playback: Setting audio source to device file...',
            );
            _currentStreamUrl =
                null; // Clear streaming URL since we're playing from file
            await _player.setFilePath(localPath);
            debugPrint(
              'Robust Playback: ✓ Audio source set, starting playback...',
            );
            await _player.play();
            debugPrint(
              'Robust Playback: ✓ Device file playback STARTED successfully',
            );

            _mode = PlaybackMode.file;
            await _persistMode();
            notifyListeners();

            // Complete the operation successfully - only clear if still current
            if (_currentPlayOperation != null &&
                !_currentPlayOperation!.isCompleted) {
              _currentPlayOperation!.complete(null);
            }
            _currentPlayOperation = null;
            // Only clear if this operation is still the current one
            if (_currentPlayOperationSongId == songId) {
              _currentPlayOperationSongId = null;
            }

            debugPrint(
              'Robust Playback: ========== PLAY REQUEST COMPLETED (Device File) ==========',
            );
            return null; // Success - no error
          } else {
            debugPrint('Robust Playback: ❌ Device file NOT FOUND: $localPath');
            throw Exception('Device file not found: $localPath');
          }
        }

        // For non-device files, check if we have a downloaded local file
        debugPrint('Robust Playback: 💾 Checking for DOWNLOADED file...');

        // Check if this song was preloaded - use preloaded path if available
        String? pathToUse = localPath;
        if (_preloadedNextSongId == songId && _preloadedNextSongPath != null) {
          debugPrint(
            'Robust Playback: ✓ Using PRELOADED path: $_preloadedNextSongPath',
          );
          pathToUse = _preloadedNextSongPath;
          // Clear preload cache
          _preloadedNextSongId = null;
          _preloadedNextSongPath = null;
        }

        if (!isDeviceFile &&
            pathToUse != null &&
            pathToUse.isNotEmpty &&
            onDeviceStatus == 'true') {
          try {
            debugPrint(
              'Robust Playback: Verifying downloaded file at: $pathToUse',
            );
            final file = File(pathToUse);
            final exists = await file.exists();
            debugPrint(
              'Robust Playback: Downloaded file ${exists ? "✓ EXISTS" : "❌ MISSING"}',
            );
            if (exists) {
              // Check if cancelled before playing downloaded file
              if (_isOperationCancelled(songId) ||
                  operationCompleter?.isCompleted == true) {
                if (operationCompleter?.isCompleted == true) {
                  final result = await operationCompleter!.future;
                  // Only treat as cancellation if result is not null (null means successful completion)
                  if (result != null) {
                    debugPrint(
                      'SimplePlaybackController: Operation cancelled via Completer before playing downloaded file for $songId: $result',
                    );
                    return result;
                  }
                  // If result is null, it means successful completion, so continue
                } else {
                  debugPrint(
                    'SimplePlaybackController: Operation cancelled before playing downloaded file for $songId',
                  );
                  return 'Operation cancelled';
                }
              }

              debugPrint(
                'Robust Playback: 🎵 Attempting to play from downloaded file',
              );

              try {
                // Set mode to file BEFORE calling setFilePath to prevent race condition
                _mode = PlaybackMode.file;
                await _persistMode();
                notifyListeners();
                debugPrint('Robust Playback: Mode set to FILE');

                // Play from local file directly
                debugPrint(
                  'Robust Playback: Setting audio source to downloaded file...',
                );
                _currentStreamUrl =
                    null; // Clear streaming URL since we're playing from file
                await _player.setFilePath(pathToUse);
                debugPrint(
                  'Robust Playback: ✓ Audio source set to downloaded file',
                );

                debugPrint('Robust Playback: Starting playback...');
                await _player.play();
                debugPrint(
                  'Robust Playback: ✓ Downloaded file playback STARTED successfully',
                );

                // Complete the operation successfully - only clear if still current
                if (_currentPlayOperation != null &&
                    !_currentPlayOperation!.isCompleted) {
                  _currentPlayOperation!.complete(null);
                }
                _currentPlayOperation = null;
                // Only clear if this operation is still the current one
                if (_currentPlayOperationSongId == songId) {
                  _currentPlayOperationSongId = null;
                }

                debugPrint(
                  'Robust Playback: ========== PLAY REQUEST COMPLETED (Downloaded File) ==========',
                );
                return null; // Success - no error
              } catch (localFileError) {
                debugPrint(
                  'Robust Playback: ❌ ERROR playing from downloaded file: $localFileError',
                );

                // Delete the corrupted file so it gets re-downloaded properly
                try {
                  if (localPath != null) {
                    final corruptedFile = File(localPath);
                    if (await corruptedFile.exists()) {
                      await corruptedFile.delete();
                      debugPrint(
                        'Robust Playback: 🗑 Deleted corrupted file: $localPath',
                      );
                    }
                  }
                } catch (deleteError) {
                  debugPrint(
                    'Robust Playback: Failed to delete corrupted file: $deleteError',
                  );
                }

                // Clear the on_device_status so it will be re-downloaded
                try {
                  await DatabaseHelper.instance.updateSong(songId, {
                    'on_device_status': 'false',
                    'on_device_filename': '',
                  });
                  debugPrint(
                    'Robust Playback: Cleared on_device_status in database',
                  );
                } catch (dbError) {
                  debugPrint(
                    'Robust Playback: Failed to update database: $dbError',
                  );
                }

                debugPrint('Robust Playback: ⚠ Falling back to STREAMING mode');
                // Fall through to streaming logic
              }
            }
          } catch (fileCheckError) {
            debugPrint(
              'Robust Playback: ❌ ERROR checking downloaded file: $fileCheckError',
            );
            debugPrint('Robust Playback: ⚠ Falling back to STREAMING mode');
            // Fall through to streaming logic
          }
        }
      }

      // Check if cancelled before server operations
      if (_isOperationCancelled(songId) ||
          operationCompleter?.isCompleted == true) {
        if (operationCompleter?.isCompleted == true) {
          final result = await operationCompleter!.future;
          // Only treat as cancellation if result is not null (null means successful completion)
          if (result != null) {
            debugPrint(
              'SimplePlaybackController: Operation cancelled via Completer before server operations for $songId: $result',
            );
            return result;
          }
          // If result is null, it means successful completion, so continue
        } else {
          debugPrint(
            'SimplePlaybackController: Operation cancelled before server operations for $songId',
          );
          return 'Operation cancelled';
        }
      }

      // If we have raw data, ensure the song exists in backend first
      if (raw != null) {
        debugPrint('Robust Playback: 📤 Ensuring song exists in backend...');
        await _ensureSongExistsInBackend(songId, raw);
        debugPrint('Robust Playback: ✓ Song backend check completed');
      }

      // ===== ON-DEVICE DOWNLOAD FLOW =====
      // Download the file via queue service (priority download for immediate playback)
      debugPrint('Robust Playback: 📥 Starting ON-DEVICE download...');

      // Get the Spotify URL from raw data or database
      debugPrint(
        'Robust Playback: 🔍 Looking for external URL (Spotify/etc)...',
      );
      String? extUrl;
      try {
        if (raw != null) {
          extUrl = raw['ext']?['spotify']?['url'] as String?;
          debugPrint('Robust Playback: External URL from raw data: $extUrl');
        } else if (row != null) {
          final extData = row['ext'];
          if (extData is String) {
            final parsed = jsonDecode(extData);
            extUrl = parsed['spotify']?['url'] as String?;
          } else if (extData is Map) {
            extUrl = extData['spotify']?['url'] as String?;
          }
          debugPrint('Robust Playback: External URL from database: $extUrl');
        }
      } catch (e) {
        debugPrint('Robust Playback: ⚠ Error extracting ext URL: $e');
      }

      // If no ext URL found locally, fetch track details from Spotify API directly
      if (extUrl == null || extUrl.isEmpty) {
        debugPrint(
          'Robust Playback: ⚠ No ext URL locally, fetching from Spotify API...',
        );
        try {
          final track = await SpotifyClient.instance.getTrack(songId);

          if (track != null) {
            extUrl = track.url ?? 'https://open.spotify.com/track/${track.id}';
            debugPrint('Robust Playback: ✓ Got ext URL from Spotify: $extUrl');

            // Update local database with the ext field and artwork
            if (extUrl.isNotEmpty) {
              try {
                final trackData = track.toSearchItem();

                // Find largest artwork image
                String? artworkLargest;
                String? artworkImages;
                if (track.images.isNotEmpty) {
                  artworkImages = jsonEncode(track.images);
                  int bestWidth = 0;
                  for (final img in track.images) {
                    final width = (img['width'] as int?) ?? 0;
                    final url = img['url'] as String?;
                    if (url != null && url.isNotEmpty && width > bestWidth) {
                      bestWidth = width;
                      artworkLargest = url;
                    }
                  }
                }

                final updateData = <String, dynamic>{
                  'ext': jsonEncode(trackData['ext']),
                };

                // Only update artwork if we got valid data
                if (artworkLargest != null && artworkLargest.isNotEmpty) {
                  updateData['artwork_largest'] = artworkLargest;
                }
                if (artworkImages != null) {
                  updateData['artwork_images'] = artworkImages;
                }

                await DatabaseHelper.instance.updateSong(songId, updateData);
                debugPrint(
                  'Robust Playback: ✓ Updated database with ext field and artwork',
                );
              } catch (e) {
                debugPrint('Robust Playback: ⚠ Failed to update song data: $e');
              }
            }
          } else {
            debugPrint('Robust Playback: ❌ Failed to fetch track from Spotify');
          }
        } catch (e) {
          debugPrint('Robust Playback: ❌ Error fetching track details: $e');
        }
      }

      if (extUrl == null || extUrl.isEmpty) {
        debugPrint('Robust Playback: ❌ FATAL: No playable source URL found');
        StatusMessageController.instance.hide();
        throw Exception('No playable source found');
      }

      debugPrint('Robust Playback: ✓ Spotify URL obtained: $extUrl');

      // Check if cancelled before downloading
      if (_isOperationCancelled(songId)) {
        debugPrint(
          'Robust Playback: 🛑 Operation cancelled before download for $songId',
        );
        return 'Operation cancelled';
      }

      // Generate unique request ID for this download
      _activeRequestId = _uuid.v4();
      debugPrint('Robust Playback: 🆔 Generated request ID: $_activeRequestId');

      // Get song title for queue display
      final songTitle = row?['title'] as String? ?? 'Unknown';

      // Download using queue service (priority download)
      debugPrint('Robust Playback: 📥 Initiating download via queue...');
      final downloadResult = await DownloadQueueService.instance
          .downloadAndWait(songId: songId, songTitle: songTitle);

      // Check if cancelled during download
      if (_isOperationCancelled(songId)) {
        debugPrint(
          'Robust Playback: 🛑 Operation cancelled during download for $songId',
        );
        StatusMessageController.instance.hide();
        return 'Operation cancelled';
      }

      if (!downloadResult.success) {
        debugPrint(
          'Robust Playback: ❌ Download FAILED: ${downloadResult.error}',
        );
        StatusMessageController.instance.hide();
        throw Exception('Download failed: ${downloadResult.error}');
      }

      final localFilePath = downloadResult.filePath!;
      debugPrint('Robust Playback: ✓ Download COMPLETED: $localFilePath');

      // Database update and notifications already handled by queue service

      // Check if cancelled before playback
      if (_isOperationCancelled(songId) ||
          operationCompleter?.isCompleted == true) {
        if (operationCompleter?.isCompleted == true) {
          final result = await operationCompleter!.future;
          if (result != null) {
            debugPrint(
              'Robust Playback: ❌ Operation cancelled via Completer before playback for $songId: $result',
            );
            return result;
          }
        } else {
          debugPrint(
            'Robust Playback: ❌ Operation cancelled before playback for $songId',
          );
          return 'Operation cancelled';
        }
      }

      // Play from local file
      debugPrint('Robust Playback: 🎵 Playing from LOCAL FILE: $localFilePath');
      _currentStreamUrl =
          null; // Clear streaming URL since we're playing from file
      await _player.setFilePath(localFilePath);
      await _player.play();
      debugPrint('Robust Playback: ✓ Local file playback STARTED');

      _mode = PlaybackMode.file;
      await _persistMode();
      notifyListeners();

      // Operation completed successfully - only clear if still current
      if (_currentPlayOperation != null &&
          !_currentPlayOperation!.isCompleted) {
        _currentPlayOperation!.complete(null);
      }
      _currentPlayOperation = null;
      // Only clear if this operation is still the current one
      if (_currentPlayOperationSongId == songId) {
        _currentPlayOperationSongId = null;
      }

      debugPrint(
        'Robust Playback: ========== PLAY REQUEST COMPLETED (Streaming) ==========',
      );
      return null;
    } catch (e) {
      final msg = 'Playback error: $e';
      debugPrint('Robust Playback: ❌❌❌ PLAYBACK ERROR: $e');
      debugPrint('Robust Playback: Stack trace: ${StackTrace.current}');
      _stopPlayTimeTracking(); // Stop tracking on error

      // Check if it was a download failure
      final errorStr = e.toString().toLowerCase();
      final isDownloadFailure =
          errorStr.contains('download') ||
          (errorStr.contains('all') && errorStr.contains('failed'));

      if (isDownloadFailure) {
        // Set error mode to show error indicators everywhere
        _mode = PlaybackMode.error;
        _lastErrorSongId = songId; // Track which song had the error
        StatusMessageController.instance.showAllAttemptsFailed();
      } else {
        _mode = PlaybackMode.stopped;
        _lastErrorSongId = null;
        StatusMessageController.instance.hide();
      }
      await _persistMode();

      // Complete THIS operation's completer with error (only if it's still active)
      if (operationCompleter != null &&
          !operationCompleter.isCompleted &&
          _currentPlayOperation == operationCompleter) {
        operationCompleter.complete(msg);
        _currentPlayOperation = null;
        debugPrint(
          'Robust Playback: ✓ Completed THIS operation\'s completer with error for songId: $songId',
        );
      } else if (operationCompleter != null &&
          _currentPlayOperation != operationCompleter) {
        debugPrint(
          'Robust Playback: ⚠ Not completing completer in catch - belongs to different operation (songId: $songId)',
        );
      }

      // Only clear songId if this operation is still the current one
      if (_currentPlayOperationSongId == songId) {
        _currentPlayOperationSongId = null;
      }

      notifyListeners();
      debugPrint('Robust Playback: ========== PLAY REQUEST FAILED ==========');
      return msg;
    } finally {
      // Ensure THIS operation's completer is always cleaned up
      // Only complete if it's still the active completer (not replaced by new operation)
      if (operationCompleter != null &&
          !operationCompleter.isCompleted &&
          _currentPlayOperation == operationCompleter) {
        operationCompleter.complete('Operation cleanup');
        _currentPlayOperation = null;
        debugPrint(
          'Robust Playback: ✓ Completed THIS operation\'s completer in finally for songId: $songId',
        );
      } else if (operationCompleter != null &&
          _currentPlayOperation != operationCompleter) {
        debugPrint(
          'Robust Playback: ⚠ Not completing completer in finally - belongs to different operation (songId: $songId)',
        );
      }

      // Only clear songId if this operation is still the current one
      // (prevents old operations from clearing new operation's songId)
      if (_currentPlayOperationSongId == songId) {
        _currentPlayOperationSongId = null;
      }
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      _pausePlayTimeTracking(); // Pause time tracking without saving
      notifyListeners();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await _player.play();
      _resumePlayTimeTracking(); // Resume time tracking
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      _stopPlayTimeTracking(); // Stop tracking play time
      await _player.stop();
      _currentStreamUrl = null; // Clear streaming URL when stopped
      _mode = PlaybackMode.stopped;
      await _persistMode();
      notifyListeners();
    } on PlatformException catch (e) {
      if (e.code == 'abort') {
        debugPrint(
          'SimplePlaybackController: Stop interrupted - continuing anyway',
        );
        _currentStreamUrl = null;
        _mode = PlaybackMode.stopped;
        await _persistMode();
        notifyListeners();
      } else {
        debugPrint(
          'SimplePlaybackController: PlatformException during stop: ${e.code}',
        );
      }
    } catch (e) {
      debugPrint('SimplePlaybackController: Error during stop: $e');
    }
  }

  Future<void> seek(Duration position) async {
    // Save play time before seeking (seeking counts as an event)
    saveCurrentPlayTime();
    await _player.seek(position);
  }

  /// Update database to mark server file as available for a specific song
  Future<void> _updateServerFileStatusForSong(String songId) async {
    try {
      debugPrint(
        'SimplePlaybackController: About to update database for songId: $songId',
      );

      // First check if the song exists in database
      final existingSong = await DatabaseHelper.instance.getSong(songId);
      if (existingSong == null) {
        debugPrint(
          'SimplePlaybackController: Song $songId not found in database, cannot update file_exists flag',
        );
        return;
      }

      debugPrint(
        'SimplePlaybackController: Song exists, current file_exists: ${existingSong['file_exists']}',
      );

      await DatabaseHelper.instance.updateSong(songId, {'file_exists': 'true'});

      // Verify the update worked
      final updatedSong = await DatabaseHelper.instance.getSong(songId);
      debugPrint(
        'SimplePlaybackController: After update, file_exists: ${updatedSong?['file_exists']}',
      );

      debugPrint(
        'SimplePlaybackController: Successfully updated server file status for $songId',
      );

      // Notify listeners so UI can update (like now playing page checkmarks)
      notifyListeners();
    } catch (e) {
      debugPrint(
        'SimplePlaybackController: Error updating server file status: $e',
      );
      debugPrint(
        'SimplePlaybackController: Stack trace: ${StackTrace.current}',
      );
    }
  }

  /// Switch from streaming to local file playback
  Future<void> switchToLocalFile(String songId, String filePath) async {
    debugPrint(
      'SimplePlaybackController: switchToLocalFile called - songId: $songId, currentSongId: $_currentSongId, mode: $_mode, processingState: ${_player.processingState}',
    );

    // Only switch if this is the currently playing song and we're streaming
    if (_currentSongId != songId || _mode != PlaybackMode.streaming) {
      debugPrint(
        'SimplePlaybackController: Not switching - wrong song ($songId vs $_currentSongId) or mode ($_mode)',
      );
      return;
    }

    // Don't interrupt if player is already loading something else
    if (_player.processingState == ProcessingState.loading) {
      debugPrint(
        'SimplePlaybackController: Player is loading, deferring local file switch',
      );
      // Retry after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (_currentSongId == songId && _mode == PlaybackMode.streaming) {
          switchToLocalFile(songId, filePath);
        }
      });
      return;
    }

    debugPrint(
      'SimplePlaybackController: Download completed, switching to local file',
    );

    try {
      debugPrint('SimplePlaybackController: Switching to local file $filePath');

      // Get current position and playing state before switching
      final currentPos = _player.position;
      final wasPlaying = _player.playing;

      // Stop current stream with error handling
      try {
        await _player.stop();
      } on PlatformException catch (e) {
        if (e.code == 'abort') {
          debugPrint(
            'SimplePlaybackController: Stop interrupted, continuing with switch',
          );
        } else {
          rethrow;
        }
      }

      // Small delay to ensure previous operation completes
      await Future.delayed(const Duration(milliseconds: 100));

      // Play from local file with error handling
      try {
        await _player.setFilePath(filePath);
        await _player.seek(currentPos); // Resume from same position

        if (wasPlaying) {
          await _player.play();
        }

        _mode = PlaybackMode.file;
        await _persistMode();
        notifyListeners();

        // Show switched to local file message
        // StatusMessageController.instance.showSwitchedToLocal(); //the switched to offline message

        debugPrint(
          'SimplePlaybackController: Successfully switched to local playback',
        );
      } on PlatformException catch (e) {
        if (e.code == 'abort') {
          debugPrint(
            'SimplePlaybackController: Local file loading interrupted - likely new song started',
          );
          // Don't restore streaming, the new song is already loading
          return;
        } else {
          rethrow;
        }
      }
    } on PlatformException catch (e) {
      debugPrint(
        'SimplePlaybackController: PlatformException switching to local file: ${e.code} - ${e.message}',
      );
      // If switching fails, continue with streaming (don't interrupt playback)
    } catch (e) {
      debugPrint('SimplePlaybackController: Error switching to local file: $e');
      // If switching fails, continue with streaming
    }
  }

  Future<void> disposeController() async {
    _notifyDebouncer?.cancel();
    _interruptionSubscription?.cancel();
    _devicesChangedSubscription?.cancel();
    await _player.dispose();
  }

  /// Debug method to check raw song data structure
  Future<void> _ensureSongExistsInBackend(
    String songId,
    Map<String, dynamic> raw,
  ) async {
    debugPrint('SimplePlaybackController: Raw song data for $songId:');
    debugPrint(jsonEncode(raw));

    // For now, just log the data to understand the structure
    // The backend should auto-create songs via /v1/files/by-song/:songId
    // if they have the proper Spotify URL in ext.spotify.url
  }

  /// Start tracking play time for the current song (event-based, no timer)
  void _startPlayTimeTracking() {
    // Save any existing play time first
    _saveAndResetPlayTime();

    // Start fresh tracking for the new song
    _playStartTime = DateTime.now();
    _playTimeSongId = _currentSongId;

    // Record as recent song immediately when playback starts
    if (_currentSongId != null) {
      DatabaseHelper.instance
          .recordRecentSong(_currentSongId!)
          .then((_) {
            _refreshRecentWheel();
          })
          .catchError((e) {
            debugPrint('Error recording recent song: $e');
            return null;
          });
      debugPrint(
        'SimplePlaybackController: Recorded $_currentSongId as recent song',
      );
    }

    debugPrint(
      'SimplePlaybackController: Started play time tracking (event-based)',
    );
  }

  /// Save accumulated play time and reset tracking
  /// Called on: pause, stop, song change, app close
  void _saveAndResetPlayTime() {
    if (_playStartTime != null && _playTimeSongId != null) {
      final elapsed = DateTime.now().difference(_playStartTime!).inSeconds;

      if (elapsed > 0) {
        MostPlayedHelper.addPlayTime(
          _playTimeSongId!,
          elapsed,
        ).catchError((e) => debugPrint('Error saving play time: $e'));
        debugPrint(
          'SimplePlaybackController: Saved ${elapsed}s of play time for $_playTimeSongId',
        );
      }
    }

    _playStartTime = null;
    _playTimeSongId = null;
  }

  /// Public method to save current play time without stopping tracking
  /// Called when app goes to background to preserve play time data
  void saveCurrentPlayTime() {
    if (_playStartTime != null && _playTimeSongId != null) {
      final elapsed = DateTime.now().difference(_playStartTime!).inSeconds;

      if (elapsed > 0) {
        MostPlayedHelper.addPlayTime(
          _playTimeSongId!,
          elapsed,
        ).catchError((e) => debugPrint('Error saving play time: $e'));
        debugPrint(
          'SimplePlaybackController: Saved ${elapsed}s of play time for $_playTimeSongId (app backgrounded)',
        );
        // Reset start time so we don't double-count
        _playStartTime = DateTime.now();
      }
    }
  }

  /// Stop tracking play time and save accumulated time
  void _stopPlayTimeTracking() {
    _saveAndResetPlayTime();
  }

  /// Pause play time tracking - saves the time played so far
  void _pausePlayTimeTracking() {
    _saveAndResetPlayTime();
    debugPrint('SimplePlaybackController: Paused play time tracking');
  }

  /// Resume play time tracking after pause
  void _resumePlayTimeTracking() {
    if (_currentSongId != null && _player.playing) {
      _playStartTime = DateTime.now();
      _playTimeSongId = _currentSongId;
      debugPrint('SimplePlaybackController: Resumed play time tracking');
    }
  }

  /// Refresh the recent wheel widget
  void _refreshRecentWheel() {
    // Use a microtask to avoid any potential UI update issues
    scheduleMicrotask(() {
      RecentWheelController.refresh().catchError((e) {
        debugPrint('Error refreshing recent wheel: $e');
      });
    });
  }

  /// Preload the next song in queue for smoother transitions
  /// Called when current song is ~80% complete
  Future<void> _preloadNextSong() async {
    if (_isPreloading) return;

    final qs = QueueService.instance;
    if (!qs.hasNext) {
      debugPrint('SimplePlaybackController: No next song to preload');
      return;
    }

    final nextIndex = qs.currentIndex + 1;
    if (nextIndex >= qs.queue.length) {
      // Wrap around if repeat is on
      if (qs.repeatMode == 0) return;
    }

    final nextId = nextIndex < qs.queue.length
        ? qs.queue[nextIndex]
        : qs.queue[0]; // Wrap to first song

    // Skip if already preloaded
    if (nextId == _preloadedNextSongId && _preloadedNextSongPath != null) {
      return;
    }

    _isPreloading = true;
    debugPrint('SimplePlaybackController: Preloading next song: $nextId');

    try {
      final row = await DatabaseHelper.instance.getSong(nextId);
      if (row == null) {
        _isPreloading = false;
        return;
      }

      final localPath = row['on_device_filename'] as String?;
      final onDeviceStatus = row['on_device_status'] as String?;

      if (localPath != null &&
          localPath.isNotEmpty &&
          onDeviceStatus == 'true') {
        final file = File(localPath);
        if (await file.exists()) {
          _preloadedNextSongId = nextId;
          _preloadedNextSongPath = localPath;
          debugPrint(
            'SimplePlaybackController: ✓ Preloaded next song path: $localPath',
          );
        }
      }
    } catch (e) {
      debugPrint('SimplePlaybackController: Error preloading next song: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// Check position and trigger preload when near end of song
  void _checkAndPreloadNextSong() {
    final duration = _player.duration;
    final position = _player.position;

    if (duration != null && duration.inMilliseconds > 0) {
      final progress = position.inMilliseconds / duration.inMilliseconds;
      // Start preloading when 80% through the song
      if (progress >= 0.8 && _preloadedNextSongId == null) {
        _preloadNextSong();
      }
    }
  }
}
