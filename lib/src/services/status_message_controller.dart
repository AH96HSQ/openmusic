import 'dart:async';
import 'package:flutter/foundation.dart';

/// Controls the status message chain with specific timing for each message
/// Manages transitions between different status states with appropriate delays
class StatusMessageController extends ChangeNotifier {
  static final StatusMessageController _instance =
      StatusMessageController._internal();
  static StatusMessageController get instance => _instance;

  StatusMessageController._internal();

  String? _currentMessage;
  Timer? _messageTimer;
  bool _isActive = false;
  String? _pendingMessage; // Store pending message while first message runs

  String? get currentMessage => _currentMessage;
  bool get isActive => _isActive;

  /// Minimum display time for non-final messages
  static const Duration _minDisplayTime = Duration(milliseconds: 1200);

  /// Timestamp when current message was shown
  DateTime? _messageShownAt;

  /// Pending message waiting for minimum time to pass
  String? _queuedMessage;

  /// Whether we're currently in downloading state
  bool _isDownloading = false;

  /// Whether we're in "trying" mode (showing method attempts)
  bool _isTrying = false;
  bool get isTrying => _isTrying;

  /// Progress value for the background progress bar (0.0 to 1.0)
  double _progress = 0.0;
  double get progress => _progress;

  /// Timer for timeout-based progress animation
  Timer? _progressTimer;
  DateTime? _methodStartTime;

  /// Timeout duration for each method's 3 retries combined (30 seconds)
  static const Duration _methodTimeout = Duration(seconds: 30);

  /// Message chain for on-device download process
  static const Map<String, Duration> _messageTimings = {
    // New on-device download messages (Duration.zero means use _minDisplayTime)
    'Trying to Download via method 1/3': Duration.zero,
    'Trying to Download via method 2/3': Duration.zero,
    'Trying to Download via method 3/3': Duration.zero,
    'Downloading': Duration.zero, // Active download, no auto-hide
    'Downloaded!': Duration(milliseconds: 2500), // Final message, auto-hides
    // Error messages
    'You seem offline!': Duration(milliseconds: 3000),
    'Download failed, try again!': Duration(milliseconds: 3000),
    // Legacy messages (kept for compatibility)
    "We don't have this file": Duration(milliseconds: 2200),
    'Finding it for you': Duration.zero,
    'Got it!': Duration(milliseconds: 2200),
    'Now Available Offline!': Duration(milliseconds: 3000),
  };

  /// Show which download method is being tried
  /// [methodName] is the name of the method being tried (e.g., 'SRA', 'DSRA', 'SMP')
  /// [isFirstAttempt] indicates if this is the first attempt for this method (resets progress)
  /// [batchCurrent] and [batchTotal] are for queue position (always provided now)
  void showTryingMethod(
    String methodName, {
    bool isFirstAttempt = true,
    int? batchCurrent,
    int? batchTotal,
  }) {
    _isActive = true;
    _isDownloading = false;
    _isTrying = true;

    // Only reset progress when starting a new method (not on retries)
    if (isFirstAttempt) {
      _progress = 0.0;
      _methodStartTime = DateTime.now();
      _startProgressTimer();
    }

    // Show method name with queue position (only if more than 1 song)
    String message;
    if (batchCurrent != null && batchTotal != null && batchTotal > 1) {
      message = '$batchCurrent/$batchTotal Trying $methodName';
    } else {
      message = 'Trying $methodName';
    }
    _showMessageWithMinTime(message);
  }

  /// Start the progress timer that fills the bar based on timeout
  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_methodStartTime == null || !_isActive) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(_methodStartTime!);
      final newProgress =
          (elapsed.inMilliseconds / _methodTimeout.inMilliseconds).clamp(
            0.0,
            1.0,
          );

      if (newProgress != _progress) {
        _progress = newProgress;
        notifyListeners();
      }

      if (_progress >= 1.0) {
        timer.cancel();
      }
    });
  }

  /// Show download progress (no percentage, progress bar shows visually)
  /// Immediately shows the downloading message, canceling any queued messages
  void showDownloading(int percentage) {
    if (!_isActive) return;

    // First call to showDownloading - need to force transition from previous message
    if (!_isDownloading) {
      _isDownloading = true;
      _isTrying = false; // Stop the loading animation
      // Cancel any queued messages and timers
      _queuedMessage = null;
      _messageTimer?.cancel();
      _progressTimer?.cancel();
      _messageShownAt = DateTime.now();
      debugPrint('📊 StatusMessage: Starting download progress display');
    }

    // Update progress based on download percentage
    _progress = percentage / 100.0;

    // Show simple "Downloading" message (progress shown via bar)
    if (_currentMessage != 'Downloading') {
      _currentMessage = 'Downloading';
      notifyListeners();
    } else {
      // Just notify for progress bar update
      notifyListeners();
    }
  }

  /// Show download complete message (final message, shows immediately)
  void showDownloaded() {
    if (!_isActive) return;
    // Final message - cancel any pending and show immediately
    _queuedMessage = null;
    _messageTimer?.cancel();
    _progressTimer?.cancel();
    _isDownloading = false;
    _progress = 1.0; // Full progress bar
    _showMessage('Downloaded!');
  }

  /// Show batch download progress (for queue downloads)
  /// [current] is the 1-based index of current song being downloaded
  /// [total] is the total number of songs in the queue
  /// [currentTitle] is the title of the currently downloading song
  /// [currentProgress] is the download progress of current song (0-100), optional
  void showBatchDownloadProgress({
    required int current,
    required int total,
    required String currentTitle,
    int? currentProgress,
  }) {
    _isActive = true;
    _isDownloading = true;
    _isTrying = false;

    // Cancel any queued messages
    _queuedMessage = null;
    _messageTimer?.cancel();
    _progressTimer?.cancel();

    // Progress bar shows current song's progress (0-100%), not collective
    _progress = currentProgress != null
        ? (currentProgress / 100.0).clamp(0.0, 1.0)
        : 0.0;

    // Truncate title if too long
    final displayTitle = currentTitle.length > 20
        ? '${currentTitle.substring(0, 17)}...'
        : currentTitle;

    // Only show x/y when more than 1 song in queue
    final message = total > 1
        ? 'Downloading $current/$total: $displayTitle'
        : 'Downloading $displayTitle';
    if (_currentMessage != message) {
      _currentMessage = message;
      _messageShownAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Show offline error message
  void showOffline() {
    _isActive = true;
    _queuedMessage = null;
    _messageTimer?.cancel();
    _isDownloading = false;
    _showMessage('You seem offline!');
  }

  /// Show all attempts failed error message
  void showAllAttemptsFailed() {
    _isActive = true;
    _queuedMessage = null;
    _messageTimer?.cancel();
    _isDownloading = false;
    _showMessage('Download failed, try again!');
  }

  /// Start the file checking message chain (legacy - kept for compatibility)
  void startFileCheckingChain() {
    if (_isActive) return;

    _isActive = true;
    _showMessage("We don't have this file");
  }

  /// Transition to Finding it for you phase (legacy)
  void showFindingAndDownloading() {
    if (!_isActive) return;

    // If first message is still running, store as pending
    if (_currentMessage == "We don't have this file" && _messageTimer != null) {
      _pendingMessage = 'Finding it for you';
      return;
    }

    _showMessage('Finding it for you');
  }

  /// Show download progress with percentage (legacy style)
  void showDownloadProgress(int percentage) {
    if (!_isActive) return;

    _showMessage('Downloading $percentage%');
  }

  /// Show completion and auto-hide after delay (legacy)
  void showComplete() {
    if (!_isActive) return;

    _showMessage('Got it!');
  }

  /// Show Now Available Offline! message when download completes
  void showSwitchedToLocal() {
    _isActive = true;
    _showMessage('Now Available Offline!');
  }

  /// Show arbitrary custom message in the status capsule
  /// Optional: supply a duration in milliseconds to override default timing
  void showMessage(String message, {Duration? duration}) {
    _isActive = true;
    if (duration != null) {
      // Temporary override: set a one-off timer for this message
      _messageTimer?.cancel();
      _currentMessage = message;
      notifyListeners();
      _messageTimer = Timer(duration, () {
        if (_currentMessage == message) hide();
      });
    } else {
      _showMessage(message);
    }
  }

  /// Cancel all timers to prevent accumulation
  void _cancelAllTimers() {
    _messageTimer?.cancel();
    _messageTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// Hide the status message and reset state
  void hide() {
    _cancelAllTimers();
    _pendingMessage = null;
    _queuedMessage = null;
    _messageShownAt = null;
    _methodStartTime = null;
    _isDownloading = false;
    _isTrying = false;
    _progress = 0.0;
    _currentMessage = null;
    _isActive = false;
    notifyListeners();
  }

  /// Smoothly exit with animation (triggered by X button)
  void smoothExit() {
    _cancelAllTimers();
    _pendingMessage = null;
    _queuedMessage = null;
    _messageShownAt = null;
    _methodStartTime = null;
    _isDownloading = false;
    _isTrying = false;
    _progress = 0.0;
    _isActive = false;
    // Set message to null to trigger exit animation
    _currentMessage = null;
    notifyListeners();
  }

  /// Show message respecting minimum display time for previous message
  void _showMessageWithMinTime(String message) {
    if (_messageShownAt != null) {
      final elapsed = DateTime.now().difference(_messageShownAt!);
      final remaining = _minDisplayTime - elapsed;

      if (remaining.inMilliseconds > 0) {
        // Previous message hasn't been shown long enough, queue this one
        _queuedMessage = message;
        _messageTimer?.cancel();
        _messageTimer = Timer(remaining, () {
          if (_queuedMessage == message) {
            _queuedMessage = null;
            _showMessage(message);
          }
        });
        return;
      }
    }
    _showMessage(message);
  }

  /// Internal method to display a message with appropriate timing
  void _showMessage(String message) {
    _messageShownAt = DateTime.now();
    _cancelAllTimers(); // Cancel all timers before showing new message
    _currentMessage = message;
    notifyListeners();

    final timing = _messageTimings[message];
    if (timing != null && timing.inMilliseconds > 0) {
      _messageTimer = Timer(timing, () {
        if (_currentMessage == message) {
          // Auto-transition to next state or hide based on message
          switch (message) {
            case "We don't have this file":
              // Check if there's a pending message to show
              if (_pendingMessage != null) {
                final pending = _pendingMessage!;
                _pendingMessage = null;
                _showMessage(pending);
              } else {
                showFindingAndDownloading();
              }
              break;
            case 'Got it!':
            case 'Downloaded!':
            case 'Method found!':
            case 'You seem offline!':
            case 'Download failed, try again!':
              hide();
              break;
            case 'Now Available Offline!':
              hide();
              break;
            default:
              // For other messages, let external events drive transitions
              break;
          }
        }
      });
    }
  }

  /// Start a complete download sequence with simulated timing
  /// This is useful for testing or when you want to run the full chain
  void startDownloadSequence() {
    startFileCheckingChain();

    // Simulate the progression through states
    Timer(const Duration(milliseconds: 4000), () {
      if (_isActive) showFindingAndDownloading();
    });

    // Simulate progress updates
    Timer(const Duration(milliseconds: 3000), () {
      if (_isActive) showDownloadProgress(15);
    });

    Timer(const Duration(milliseconds: 3500), () {
      if (_isActive) showDownloadProgress(35);
    });

    Timer(const Duration(milliseconds: 4000), () {
      if (_isActive) showDownloadProgress(60);
    });

    Timer(const Duration(milliseconds: 4500), () {
      if (_isActive) showDownloadProgress(85);
    });

    Timer(const Duration(milliseconds: 5000), () {
      if (_isActive) showComplete();
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }
}
