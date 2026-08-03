import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import '../ui/widgets/most_played_wheel.dart';
import '../ui/widgets/song_tile.dart';
import '../services/recommendation_service.dart';
import '../services/status_message_controller.dart';
import '../data/database_helper.dart';
import '../services/queue_service.dart';
import '../ui/pages/add_to_playlist_bottom_sheet.dart';
import '../helpers/music_navigation_helper.dart';
import '../services/simple_playback_controller.dart';
import '../ui/widgets/album_art_widget.dart';
import '../ui/widgets/liked_heart.dart';

class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage>
    with SingleTickerProviderStateMixin {
  bool _isCalculating = false;
  List<Map<String, dynamic>> _recommendations = [];
  late final RecommendationService _recommendationService;
  RecommendationProgress? _progress;
  Timer? _messageRotationTimer;
  String _currentDisplayMessage = '';

  // Animated progress value
  late AnimationController _progressAnimationController;
  late Animation<double> _progressAnimation;
  double _currentProgressValue = 0.0;
  double _targetProgressValue = 0.0;

  // Fun messages to rotate through
  final List<String> _funMessages = [
    'Analyzing your taste...',
    "You've been listening to some cool songs!",
    "I'm the smartest AI by the way!",
    'Listening to every music on the planet',
    'Almost there',
    'Finding the perfect tracks',
    'Digging through millions of songs',
    'Your music taste is fire!',
    'Calculating vibes',
  ];
  int _currentMessageIndex = 0;
  @override
  void initState() {
    super.initState();
    _recommendationService = RecommendationService();

    // Initialize animation controller for smooth progress transitions
    _progressAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 4000,
      ), // Slower 2 second transition
    );

    _progressAnimation =
        Tween<double>(begin: 0.0, end: 0.0).animate(
          CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeInOut,
          ),
        )..addListener(() {
          setState(() {
            _currentProgressValue = _progressAnimation.value;
          });
        });

    // Listen to progress updates
    _recommendationService.progressStream.listen((progress) {
      // Update target progress and animate to it
      _targetProgressValue = progress.percentage / 100.0;
      _animateProgressTo(_targetProgressValue);

      setState(() {
        // Check if this is the "Stealing your new songs" message
        final isStealingSongsMessage = progress.message.startsWith(
          'Stealing your new songs',
        );

        // If stealing songs, use that message; otherwise use rotating message
        _progress = progress.copyWith(
          message: isStealingSongsMessage
              ? progress.message
              : (_currentDisplayMessage.isNotEmpty
                    ? _currentDisplayMessage
                    : progress.message),
          secondaryMessage: null, // Never show secondary message (song names)
        );

        // Stop message rotation when stealing songs phase starts
        if (isStealingSongsMessage && _messageRotationTimer != null) {
          _messageRotationTimer?.cancel();
          _messageRotationTimer = null;
        }
      });
    });

    _loadCachedRecommendations();
  }

  void _animateProgressTo(double target) {
    _progressAnimation =
        Tween<double>(begin: _currentProgressValue, end: target).animate(
          CurvedAnimation(
            parent: _progressAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    _progressAnimationController.reset();
    _progressAnimationController.forward();
  }

  void _startMessageRotation() {
    _currentMessageIndex = 0;
    _currentDisplayMessage = _funMessages[0];

    // Rotate messages every 4 seconds (slower)
    _messageRotationTimer?.cancel();
    _messageRotationTimer = Timer.periodic(const Duration(seconds: 12), (
      timer,
    ) {
      if (!_isCalculating) {
        timer.cancel();
        return;
      }

      setState(() {
        _currentMessageIndex = (_currentMessageIndex + 1) % _funMessages.length;
        _currentDisplayMessage = _funMessages[_currentMessageIndex];

        // Update progress with new message
        if (_progress != null) {
          _progress = _progress!.copyWith(message: _currentDisplayMessage);
        }
      });
    });
  }

  void _stopMessageRotation() {
    _messageRotationTimer?.cancel();
    _messageRotationTimer = null;
    _currentDisplayMessage = '';
    _currentProgressValue = 0.0;
    _targetProgressValue = 0.0;
  }

  /// Load cached recommendations from SharedPreferences
  Future<void> _loadCachedRecommendations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('latest_recommendations');

      if (cachedJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        final recommendations = decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        setState(() {
          _recommendations = recommendations;
        });

        debugPrint(
          'RecommendationsPage: Loaded ${recommendations.length} cached recommendations',
        );
      }
    } catch (e) {
      debugPrint(
        'RecommendationsPage: Error loading cached recommendations: $e',
      );
    }
  }

  /// Save recommendations to SharedPreferences
  Future<void> _saveRecommendationsToCache(
    List<Map<String, dynamic>> recommendations,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(recommendations);
      await prefs.setString('latest_recommendations', json);

      // Also save timestamp
      await prefs.setString(
        'latest_recommendations_timestamp',
        DateTime.now().toIso8601String(),
      );

      debugPrint(
        'RecommendationsPage: Saved ${recommendations.length} recommendations to cache',
      );
    } catch (e) {
      debugPrint(
        'RecommendationsPage: Error saving recommendations to cache: $e',
      );
    }
  }

  @override
  void dispose() {
    _stopMessageRotation();
    _progressAnimationController.dispose();
    _recommendationService.dispose();
    super.dispose();
  }

  Future<void> _calculateRecommendations() async {
    setState(() {
      _isCalculating = true;
      // Don't reset _progress to null, let it be updated by stream
    });

    // Start rotating messages
    _startMessageRotation();

    try {
      final recommendations = await _recommendationService
          .calculateRecommendations();

      // Save to SharedPreferences
      await _saveRecommendationsToCache(recommendations);

      // Stop message rotation
      _stopMessageRotation();

      setState(() {
        _recommendations = recommendations;
        _isCalculating = false;
        _progress = null;
      });

      // Show success message that auto-dismisses after 5 seconds
      StatusMessageController.instance.showMessage(
        'Found ${recommendations.length} recommendations!',
      );
      Future.delayed(const Duration(seconds: 5), () {
        StatusMessageController.instance.hide();
      });
    } catch (e) {
      // Stop message rotation on error
      _stopMessageRotation();

      setState(() {
        _isCalculating = false;
        _progress = null;
      });

      StatusMessageController.instance.showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Calculate Recommendations Button (always visible)
              SizedBox(
                width: double.infinity,
                height: 80,
                child: FilledButton(
                  onPressed: _isCalculating ? null : _calculateRecommendations,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    disabledBackgroundColor: cs.primary.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: _isCalculating && _progress != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LinearProgressIndicator(
                              value: _currentProgressValue,
                              backgroundColor: cs.onPrimary.withValues(
                                alpha: 0.3,
                              ),
                              color: cs.onPrimary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _progress!.message,
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isCalculating)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.auto_awesome,
                                    color: cs.onPrimary,
                                    size: 24,
                                  ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    _isCalculating
                                        ? 'Calculating...'
                                        : 'Calculate Recommendations',
                                    style: TextStyle(
                                      color: cs.onPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Most Played Wheel
              Text(
                'Most Played',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              MostPlayedWheel(),

              const SizedBox(height: 32),

              // Recommendations Section (always visible)
              // Centered Title
              Center(
                child: Text(
                  'Recommendations',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Recommendations list
              if (_recommendations.isEmpty && !_isCalculating)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'Click the Calculate Recommendations button to get your new recommendations!',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ..._recommendations.map((track) {
                  final songId = track['id'] as String;
                  final title = track['title'] as String? ?? 'Unknown';
                  final artists =
                      track['artists'] as String? ??
                      'Unknown Artist'; // Get artists from recommendation data

                  return _RecommendationTile(
                    key: ValueKey(songId),
                    songId: songId,
                    title: title,
                    artists: artists, // Pass artists
                    onDislike: () async {
                      final isNowDisliked = await DatabaseHelper.instance
                          .toggleDislikedStatus(songId);
                      // Don't remove from list - just let the tile grey itself out
                      // The tile will check disliked status and update its opacity

                      StatusMessageController.instance.showMessage(
                        isNowDisliked
                            ? 'Song disliked - won\'t appear in future recommendations'
                            : 'Song un-disliked - may appear in recommendations again',
                      );
                      Future.delayed(const Duration(seconds: 3), () {
                        StatusMessageController.instance.hide();
                      });
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom tile for recommendations with dislike icon
class _RecommendationTile extends StatefulWidget {
  final String songId;
  final String title;
  final String artists; // NEW: Pass artists directly
  final VoidCallback onDislike;

  const _RecommendationTile({
    super.key,
    required this.songId,
    required this.title,
    required this.artists, // NEW
    required this.onDislike,
  });

  @override
  State<_RecommendationTile> createState() => _RecommendationTileState();
}

class _RecommendationTileState extends State<_RecommendationTile> {
  bool _isDisliked = false;

  @override
  void initState() {
    super.initState();
    _checkDislikedStatus();
  }

  Future<void> _checkDislikedStatus() async {
    final song = await DatabaseHelper.instance.getSong(widget.songId);
    if (song != null && mounted) {
      final status = song['disliked_status'];
      setState(() {
        _isDisliked =
            (status == 1 ||
            status == '1' ||
            status == 'true' ||
            status == true);
      });
    }
  }

  Future<void> _handleDislike() async {
    widget.onDislike();
    // After dislike, check status again (in case it was toggled off)
    await Future.delayed(const Duration(milliseconds: 100));
    await _checkDislikedStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _isDisliked ? 0.4 : 1.0, // Grey out if disliked
      child: _RecommendationTileContent(
        songId: widget.songId,
        title: widget.title,
        artists: widget.artists, // Pass artists through
        onTap: () async {
          // Play the song when tapped
          final song = await DatabaseHelper.instance.getSong(widget.songId);
          if (song != null) {
            final currentSongId =
                SimplePlaybackController.instance.currentSongId;
            final isExactSamePlayback = currentSongId == widget.songId;

            if (isExactSamePlayback) {
              // Toggle play/pause if same song
              if (SimplePlaybackController.instance.isPlaying) {
                await SimplePlaybackController.instance.pause();
              } else {
                await SimplePlaybackController.instance.resume();
              }
            } else {
              // Play new song from recommendations
              await QueueService.instance.setQueue(
                [widget.songId],
                startIndex: 0,
                context: PlaybackContext.playlist,
              );
              final err = await SimplePlaybackController.instance.play(
                widget.songId,
                song,
              );
              if (err != null) {
                debugPrint('Playback error: $err');
              }
            }
          }
        },
        onDislike: _handleDislike,
        menuOptions: [
          PopupMenuOption(
            id: 'play_next',
            label: 'Play Next',
            onSelected: () async {
              await QueueService.instance.playNext(widget.songId);
              StatusMessageController.instance.showMessage(
                'Will play "${widget.title}" next',
                duration: const Duration(milliseconds: 2200),
              );
            },
          ),
          PopupMenuOption(
            id: 'add_to_queue',
            label: 'Add to Queue',
            onSelected: () async {
              await QueueService.instance.addToQueue(widget.songId);
              StatusMessageController.instance.showMessage(
                'Added "${widget.title}" to queue',
                duration: const Duration(milliseconds: 2200),
              );
            },
          ),
          PopupMenuOption(
            id: 'add_to_playlist',
            label: 'Add to playlist',
            onSelected: () {
              showAddToPlaylistBottomSheet(
                context,
                widget.songId,
                songTitle: widget.title,
              );
            },
          ),
          ...MusicNavigationHelper.createNavigationMenuOptions(
            context,
            widget.songId,
          ),
        ],
      ),
    );
  }
}

/// Custom tile content with Row-based layout to avoid z-index issues
class _RecommendationTileContent extends StatelessWidget {
  final String songId;
  final String title;
  final String artists; // NEW: Pass artists directly
  final VoidCallback onTap;
  final VoidCallback onDislike;
  final List<PopupMenuOption> menuOptions;

  const _RecommendationTileContent({
    required this.songId,
    required this.title,
    required this.artists, // NEW
    required this.onTap,
    required this.onDislike,
    required this.menuOptions,
  });

  @override
  Widget build(BuildContext context) {
    // No more FutureBuilder! Use the data passed from parent
    return Padding(
      padding: const EdgeInsets.only(left: 5.0, top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          // Main tappable area (album art + text content)
          Expanded(
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              child: Row(
                children: [
                  // Album art
                  AlbumArtWidget(songId: songId, width: 56, height: 56),
                  const SizedBox(width: 15),

                  // Title + artists column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title, // Use passed title directly
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artists, // Use passed artists directly
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 25),

          // Right side icons with consistent spacing
          _PlaybackIndicator(songId: songId),
          const SizedBox(width: 15),
          TappableLikedHeart(
            songId: songId,
            size: 24,
            onBeforeToggle: () async {
              // Song is already in DB from recommendations
            },
          ),
          const SizedBox(width: 4),
          // Dislike button (tight spacing)
          SizedBox(
            width: 28,
            child: IconButton(
              icon: Icon(
                Icons.do_not_disturb_on_outlined,
                color: Theme.of(
                  context,
                ).iconTheme.color?.withValues(alpha: 0.7),
                size: 22,
              ),
              onPressed: onDislike,
              tooltip: 'Dislike',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 40),
              splashRadius: 18,
            ),
          ),
          // 3-dot menu (tight spacing, compact button)
          SizedBox(
            width: 28,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              splashRadius: 18,
              iconSize: 22,
              color: Theme.of(context).colorScheme.surface,
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).iconTheme.color,
                size: 22,
              ),
              offset: const Offset(0, 40),
              onSelected: (value) {
                FocusScope.of(context).unfocus();
                final opt = menuOptions.firstWhere(
                  (o) => o.id == value,
                  orElse: () => menuOptions.first,
                );
                if (opt.onSelected != null) opt.onSelected!();
              },
              itemBuilder: (ctx) => menuOptions
                  .map(
                    (o) => PopupMenuItem<String>(
                      value: o.id,
                      child: Text(o.label),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Playback indicator widget using StreamBuilder (like MostPlayedWheel)
class _PlaybackIndicator extends StatelessWidget {
  final String songId;
  const _PlaybackIndicator({required this.songId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: SimplePlaybackController.instance.playerStateStream,
      builder: (context, snapshot) {
        final pc = SimplePlaybackController.instance;
        final playerState = snapshot.data;
        final isCurrentSong = pc.currentSongId == songId;

        if (!isCurrentSong) {
          return const SizedBox(width: 20, height: 20);
        }

        final isLoading = pc.mode == PlaybackMode.loading;
        final isError =
            pc.mode == PlaybackMode.error && pc.lastErrorSongId == songId;
        final isPlaying =
            playerState?.playing == true &&
            (pc.mode == PlaybackMode.streaming || pc.mode == PlaybackMode.file);

        // Show error icon when download failed for this song
        if (isError) {
          return const SizedBox(
            width: 20,
            height: 20,
            child: Icon(Icons.error_outline, color: Colors.red, size: 20),
          );
        }

        // Only show loading animation when actively loading
        if (isLoading) {
          return SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: LoadingAnimationWidget.threeArchedCircle(
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
          );
        }

        if (isPlaying) {
          // Show visualizer when playing
          return MiniMusicVisualizer(
            color: Theme.of(context).colorScheme.primary,
            width: 4,
            height: 15,
            radius: 2,
            animate: true,
          );
        }

        // Show paused indicator when not loading and not playing
        return SizedBox(
          width: 20,
          height: 20,
          child: Icon(
            Icons.pause,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        );
      },
    );
  }
}
