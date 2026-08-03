import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:animate_gradient/animate_gradient.dart';
import '../../data/database_helper.dart';
import '../widgets/album_art_widget.dart';
import '../widgets/auto_scroll_text.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/sync_service.dart';
import '../../services/auth_service.dart';
import '../../services/status_message_controller.dart';
import '../../services/download_helper.dart';
import '../../pages/crypto_payment_page.dart';
import 'queue_bottom_sheet.dart';
import 'add_to_playlist_bottom_sheet.dart';
import '../../services/queue_service.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/liked_songs_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../widgets/auth_widget.dart';

/// Check if running on desktop platform
bool get _isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Now Playing page - SIMPLE VERSION without animations
class NowPlayingPage extends StatefulWidget {
  final String songId;
  final VoidCallback? onNavigateToLibrary;

  const NowPlayingPage({
    super.key,
    required this.songId,
    this.onNavigateToLibrary,
  });

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final pc = SimplePlaybackController.instance;
  final syncService = SyncService.instance;
  Map<String, dynamic>? _currentSongData;
  Map<String, dynamic>? _previousSongData;
  Map<String, dynamic>? _nextSongData;
  String? _lastSongId;

  late PageController _pageController;
  bool _isPageChanging = false;
  bool _isCarouselUpdating = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1); // Start at middle page
    pc.addListener(_onPc);
    QueueService.instance.initialize();
    QueueService.instance.addListener(_onSvc);
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    _loadAllSongData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    pc.removeListener(_onPc);
    QueueService.instance.removeListener(_onSvc);
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    super.dispose();
  }

  /// Called when a download completes - refresh song data to update menu options
  void _onDownloadComplete(String songId) {
    if (songId == currentSongId && mounted) {
      _loadAllSongData();
    }
  }

  String? get currentSongId {
    return pc.currentSongId ??
        QueueService.instance.currentSongId ??
        widget.songId;
  }

  Future<void> _loadAllSongData([String? forceSongId]) async {
    final songId = forceSongId ?? currentSongId;
    if (songId == null || songId.isEmpty) return;

    debugPrint(
      'Carousel: Loading song data for songId: $songId (forced: ${forceSongId != null})',
    );

    try {
      // Load current song
      final current = await DatabaseHelper.instance.getSong(songId);

      // Load previous song if exists
      Map<String, dynamic>? previous;
      final queue = QueueService.instance.queue;
      final currentIdx = QueueService.instance.currentIndex;

      debugPrint(
        'Carousel: Queue index=$currentIdx, queue length=${queue.length}',
      );
      debugPrint(
        'Carousel: Current song in queue: ${queue[currentIdx]} (should match: $songId)',
      );

      if (queue.length > 1 && currentIdx > 0) {
        final prevId = queue[currentIdx - 1];
        debugPrint('Carousel: Loading previous song: $prevId');
        try {
          previous = await DatabaseHelper.instance.getSong(prevId);
        } catch (e) {
          debugPrint('Error loading previous song: $e');
        }
      } else if (queue.length > 1 && QueueService.instance.repeatMode != 0) {
        // If at beginning but repeat is on, load last song
        final prevId = queue[queue.length - 1];
        debugPrint('Carousel: Loading previous song (wrap): $prevId');
        try {
          previous = await DatabaseHelper.instance.getSong(prevId);
        } catch (e) {
          debugPrint('Error loading previous song: $e');
        }
      }

      // Load next song if exists
      Map<String, dynamic>? next;
      if (queue.length > 1 && currentIdx < queue.length - 1) {
        final nextId = queue[currentIdx + 1];
        debugPrint('Carousel: Loading next song: $nextId');
        try {
          next = await DatabaseHelper.instance.getSong(nextId);
        } catch (e) {
          debugPrint('Error loading next song: $e');
        }
      } else if (queue.length > 1 && QueueService.instance.repeatMode != 0) {
        // If at end but repeat is on, load first song
        final nextId = queue[0];
        debugPrint('Carousel: Loading next song (wrap): $nextId');
        try {
          next = await DatabaseHelper.instance.getSong(nextId);
        } catch (e) {
          debugPrint('Error loading next song: $e');
        }
      }

      if (mounted) {
        setState(() {
          _currentSongData = current;
          _previousSongData = previous;
          _nextSongData = next;
          _lastSongId = songId;
        });
        debugPrint(
          'Carousel: State updated - prev=${previous?['title']}, current=${current?['title']}, next=${next?['title']}',
        );
      }
    } catch (e) {
      debugPrint('Error loading song data: $e');
    }
  }

  void _onPc() {
    debugPrint(
      'Carousel: _onPc called - _isPageChanging=$_isPageChanging, _isCarouselUpdating=$_isCarouselUpdating',
    );

    // Don't interfere if we're already changing pages or updating carousel
    if (_isPageChanging || _isCarouselUpdating) {
      debugPrint('Carousel: _onPc blocked by flags');
      return;
    }

    final actualCurrentId = currentSongId;
    if (actualCurrentId != null &&
        actualCurrentId.isNotEmpty &&
        actualCurrentId != _lastSongId) {
      debugPrint(
        'Carousel: _onPc calling _loadAllSongData for $actualCurrentId',
      );
      _loadAllSongData();
    }
    if (mounted) setState(() {});
  }

  void _onSvc() {
    debugPrint(
      'Carousel: _onSvc called - _isPageChanging=$_isPageChanging, _isCarouselUpdating=$_isCarouselUpdating',
    );

    // Don't interfere if we're already changing pages or updating carousel
    if (_isPageChanging || _isCarouselUpdating) {
      debugPrint('Carousel: _onSvc blocked by flags');
      return;
    }

    final queueCurrentId = QueueService.instance.currentSongId;
    if (queueCurrentId != null &&
        queueCurrentId.isNotEmpty &&
        queueCurrentId != _lastSongId) {
      debugPrint(
        'Carousel: _onSvc calling _loadAllSongData for $queueCurrentId',
      );
      _loadAllSongData();
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPageChanged(int page) async {
    debugPrint('Carousel: _onPageChanged called with page=$page');

    // Ignore if we're on the center page (shouldn't happen but safety check)
    if (page == 1) {
      debugPrint('Carousel: Already on center page, nothing to do');
      return;
    }

    if (_isPageChanging) {
      debugPrint(
        'Carousel: Page change already in progress, resetting immediately (page: $page)',
      );
      // Reset immediately - don't wait
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(1);
      }
      return;
    }

    // Set flags immediately to prevent _onSvc interference and disable buttons
    if (mounted) {
      setState(() {
        _isPageChanging = true;
        _isCarouselUpdating = true;
      });
    }
    debugPrint(
      'Carousel: Flags set - _isPageChanging=$_isPageChanging, _isCarouselUpdating=$_isCarouselUpdating, buttons disabled',
    );

    debugPrint('Carousel: Page changed to $page - starting carousel update');

    try {
      // page 0 = previous, page 1 = current, page 2 = next
      if (page == 0 && QueueService.instance.hasPrevious) {
        // Swiped to previous
        debugPrint('Carousel: Moving to PREVIOUS song');
        await QueueService.instance.moveToPrevious();
        final prevSongId = QueueService.instance.currentSongId;
        if (prevSongId != null) {
          try {
            // Don't await pc.play() as it might hang the carousel
            pc.play(prevSongId, null);
            debugPrint('Carousel: pc.play called (not awaiting)');
            // Wait for swipe animation to complete, then update content and jump back
            debugPrint('Carousel: Waiting for swipe animation to complete...');
            await Future.delayed(
              const Duration(milliseconds: 400),
            ); // Let user see the slide

            debugPrint('Carousel: Loading new song data after animation...');
            await _loadAllSongData(prevSongId);

            debugPrint('Carousel: Jumping back to center with new content');
            if (mounted) {
              _pageController.jumpToPage(1);
            }
          } catch (e) {
            debugPrint('Carousel: Exception during song change: $e');
          }
        }
      } else if (page == 2 && QueueService.instance.hasNext) {
        // Swiped to next
        debugPrint('Carousel: Moving to NEXT song');
        await QueueService.instance.moveToNext();
        final nextSongId = QueueService.instance.currentSongId;
        debugPrint('Carousel: Got nextSongId: $nextSongId');
        if (nextSongId != null) {
          try {
            debugPrint('Carousel: About to call pc.play for $nextSongId');
            // Don't await pc.play() as it might hang the carousel
            pc.play(nextSongId, null);
            debugPrint('Carousel: pc.play called (not awaiting)');
            // Wait for swipe animation to complete, then update content and jump back
            debugPrint('Carousel: Waiting for swipe animation to complete...');
            await Future.delayed(
              const Duration(milliseconds: 400),
            ); // Let user see the slide

            debugPrint('Carousel: Loading new song data after animation...');
            await _loadAllSongData(nextSongId);

            debugPrint('Carousel: Jumping back to center with new content');
            if (mounted) {
              _pageController.jumpToPage(1);
            }
          } catch (e) {
            debugPrint('Carousel: Exception during song change: $e');
          }
        } else {
          debugPrint('Carousel: nextSongId is null!');
        }
      } else if (page != 1) {
        // Invalid swipe, go back to middle
        debugPrint('Carousel: Invalid swipe, returning to middle');
        if (mounted) {
          _pageController.animateToPage(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } finally {
      // Add a small delay before clearing carousel updating to prevent _onPc interference
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _isPageChanging = false;
          _isCarouselUpdating = false;
        });
      }
      debugPrint('Carousel: Page change completed, buttons re-enabled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final songId = currentSongId ?? '';

    // Use LayoutBuilder to get actual available space (important for desktop side panel)
    return LayoutBuilder(
      builder: (context, constraints) {
        // On desktop (constrained panel), use constraints; on mobile, use MediaQuery
        final mediaSize = MediaQuery.of(context).size;
        final isConstrained = constraints.maxWidth < mediaSize.width * 0.9;

        final screenHeight = isConstrained
            ? constraints.maxHeight
            : mediaSize.height;
        final screenWidth = isConstrained
            ? constraints.maxWidth
            : mediaSize.width;

        // Build carousel items based on what songs are available
        final carouselItems = <Widget>[];
        final queue = QueueService.instance.queue;
        final hasPrev = _previousSongData != null;
        final hasNext = _nextSongData != null;

        if (hasPrev) {
          // Use songId from _previousSongData to ensure album art syncs with title/artist
          final prevQueue =
              queue.isNotEmpty && QueueService.instance.currentIndex > 0
              ? queue[QueueService.instance.currentIndex - 1]
              : (queue.isNotEmpty && QueueService.instance.repeatMode != 0
                    ? queue[queue.length - 1]
                    : '');
          final displayPrevSongId =
              _previousSongData?['id'] as String? ?? prevQueue;
          carouselItems.add(
            _buildSongContent(
              _previousSongData,
              displayPrevSongId,
              screenWidth,
              screenHeight,
            ),
          );
        } else {
          carouselItems.add(Container()); // Empty placeholder
        }

        // Current song (always in the middle)
        // Use songId from _currentSongData to ensure album art syncs with title/artist
        final displaySongId = _currentSongData?['id'] as String? ?? songId;
        carouselItems.add(
          _buildSongContent(
            _currentSongData,
            displaySongId,
            screenWidth,
            screenHeight,
          ),
        );

        if (hasNext) {
          // Use songId from _nextSongData to ensure album art syncs with title/artist
          final nextQueue =
              queue.isNotEmpty &&
                  QueueService.instance.currentIndex < queue.length - 1
              ? queue[QueueService.instance.currentIndex + 1]
              : (queue.isNotEmpty && QueueService.instance.repeatMode != 0
                    ? queue[0]
                    : '');
          final displayNextSongId =
              _nextSongData?['id'] as String? ?? nextQueue;
          carouselItems.add(
            _buildSongContent(
              _nextSongData,
              displayNextSongId,
              screenWidth,
              screenHeight,
            ),
          );
        } else {
          carouselItems.add(Container()); // Empty placeholder
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _isDesktopPlatform
              ? _buildDesktopContent(
                  context,
                  songId,
                  carouselItems,
                  screenWidth,
                  screenHeight,
                )
              : SafeArea(
                  child: _buildMobileContent(
                    context,
                    songId,
                    carouselItems,
                    screenWidth,
                    screenHeight,
                  ),
                ),
        );
      },
    );
  }

  /// Desktop layout - centered content without SafeArea
  Widget _buildDesktopContent(
    BuildContext context,
    String songId,
    List<Widget> carouselItems,
    double screenWidth,
    double screenHeight,
  ) {
    return Column(
      children: [
        // Top bar with Donate and Queue
        Padding(
          padding: EdgeInsets.only(
            left: screenWidth * 0.05,
            right: screenWidth * 0.05,
            top: 16,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Donate chip
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CryptoPaymentPage(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Donate',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right: Cloud sync icon and queue icon
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSyncStatusIcon(context, size: 24),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: () async {
                      await showQueueBottomSheet(context);
                    },
                    icon: Icon(
                      Icons.queue_music,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Centered main content
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Album art and song info from carousel (current song only)
                  SizedBox(
                    width: screenWidth,
                    child: carouselItems.length > 1
                        ? carouselItems[1] // Current song is always at index 1
                        : carouselItems[0],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Controls at bottom
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _buildPlaybackControls(
            context,
            songId,
            screenWidth,
            isDesktop: true,
          ),
        ),
      ],
    );
  }

  /// Mobile layout - original content with SafeArea
  Widget _buildMobileContent(
    BuildContext context,
    String songId,
    List<Widget> carouselItems,
    double screenWidth,
    double screenHeight,
  ) {
    return Column(
      children: [
        // Top bar
        Padding(
          padding: EdgeInsets.only(
            left: screenWidth * 0.065,
            right: screenWidth * 0.05,
            top: screenHeight * 0.03,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Donate chip
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CryptoPaymentPage(),
                    ),
                  );
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.03,
                    vertical: screenHeight * 0.008,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(screenWidth * 0.04),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        size: screenWidth * 0.045,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(width: screenWidth * 0.015),
                      Text(
                        'Donate',
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right: Cloud sync icon and queue icon
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cloud sync icon
                  _buildSyncStatusIcon(context, size: screenWidth * 0.073),
                  SizedBox(width: screenWidth * 0.01),
                  // Queue icon
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: screenWidth * 0.073,
                      minHeight: screenWidth * 0.073,
                    ),
                    onPressed: () async {
                      await showQueueBottomSheet(context);
                    },
                    icon: Icon(
                      Icons.queue_music,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: screenWidth * 0.073,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Swipeable song content carousel
        SizedBox(
          height: screenHeight * 0.65,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: _isPageChanging
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: carouselItems.length,
            itemBuilder: (context, index) {
              return SingleChildScrollView(child: carouselItems[index]);
            },
          ),
        ),

        // Controls
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.065),
          child: _buildPlaybackControls(
            context,
            songId,
            screenWidth,
            isDesktop: false,
          ),
        ),
        SizedBox(height: screenHeight * 0.0),
      ],
    );
  }

  /// Build playback controls (shared between mobile and desktop)
  Widget _buildPlaybackControls(
    BuildContext context,
    String songId,
    double screenWidth, {
    required bool isDesktop,
  }) {
    final iconSize = isDesktop ? 28.0 : screenWidth * 0.078;
    final smallIconSize = isDesktop ? 24.0 : screenWidth * 0.0625;

    return Row(
      children: [
        // Left side: Repeat button only
        IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: smallIconSize,
            minHeight: smallIconSize,
          ),
          onPressed: songId.isNotEmpty
              ? () async {
                  await QueueService.instance.cycleRepeatMode();
                }
              : null,
          icon: Icon(
            QueueService.instance.repeatMode == 2
                ? Icons.repeat_one
                : Icons.repeat,
            color: songId.isEmpty
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                : (QueueService.instance.repeatMode == 0
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.primary),
            size: iconSize,
          ),
        ),

        // Playback controls (centered)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous button
              StreamBuilder<Duration>(
                stream: pc.positionStream,
                builder: (context, positionSnapshot) {
                  final currentPosition =
                      positionSnapshot.data ?? Duration.zero;
                  final moreThan7Seconds = currentPosition.inSeconds > 7;
                  final hasPrevious = QueueService.instance.hasPrevious;
                  final canUsePrevious =
                      songId.isNotEmpty && (moreThan7Seconds || hasPrevious);

                  return IconButton(
                    onPressed: canUsePrevious && !_isPageChanging
                        ? () async {
                            if (moreThan7Seconds) {
                              await pc.seek(Duration.zero);
                            } else if (hasPrevious && !_isPageChanging) {
                              if (isDesktop) {
                                // Desktop: directly play previous song
                                await QueueService.instance.moveToPrevious();
                                final prevSongId =
                                    QueueService.instance.currentSongId;
                                if (prevSongId != null) {
                                  await pc.play(prevSongId, null);
                                }
                              } else if (_pageController.hasClients) {
                                // Mobile: animate carousel
                                await _pageController.animateToPage(
                                  0,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            }
                          }
                        : null,
                    icon: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        canUsePrevious && !_isPageChanging
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.4),
                        BlendMode.srcIn,
                      ),
                      child: Icon(Icons.skip_previous, size: iconSize),
                    ),
                  );
                },
              ),
              // Play/Pause button
              Container(
                width: isDesktop ? 56 : screenWidth * 0.156,
                height: isDesktop ? 56 : screenWidth * 0.156,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: StreamBuilder<PlayerState>(
                  stream: pc.playerStateStream,
                  builder: (context, snapshot) {
                    final isLoading = pc.mode == PlaybackMode.loading;
                    final isError = pc.mode == PlaybackMode.error;
                    final isPlaying = pc.isPlaying;
                    final isStopped = pc.mode == PlaybackMode.stopped;

                    if (isLoading) {
                      return Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: LoadingAnimationWidget.threeArchedCircle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                      );
                    }

                    if (isError) {
                      return IconButton(
                        onPressed: () async {
                          if (songId.isNotEmpty) {
                            await pc.play(songId, null);
                          }
                        },
                        icon: Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        iconSize: isDesktop ? 32 : screenWidth * 0.094,
                      );
                    }

                    return IconButton(
                      onPressed: () async {
                        if (songId.isEmpty) {
                          final queueSongId =
                              QueueService.instance.currentSongId;
                          if (queueSongId != null && queueSongId.isNotEmpty) {
                            await pc.play(queueSongId, null);
                            return;
                          }
                          if (widget.onNavigateToLibrary != null) {
                            widget.onNavigateToLibrary!();
                          } else {
                            Navigator.of(context).pop();
                          }
                          return;
                        }

                        if (pc.mode == PlaybackMode.stopped) {
                          await pc.play(songId, null);
                        } else if (pc.isPlaying) {
                          await pc.pause();
                        } else {
                          await pc.play(songId, null);
                        }
                      },
                      icon: Icon(
                        (isPlaying && !isStopped)
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      iconSize: isDesktop ? 32 : screenWidth * 0.094,
                    );
                  },
                ),
              ),

              // Next button
              IconButton(
                onPressed:
                    songId.isNotEmpty &&
                        QueueService.instance.hasNext &&
                        !_isPageChanging
                    ? () async {
                        if (isDesktop) {
                          // Desktop: directly play next song
                          await QueueService.instance.moveToNext();
                          final nextSongId =
                              QueueService.instance.currentSongId;
                          if (nextSongId != null) {
                            await pc.play(nextSongId, null);
                          }
                        } else if (_pageController.hasClients &&
                            !_isPageChanging) {
                          // Mobile: animate carousel
                          await _pageController.animateToPage(
                            2,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      }
                    : null,
                icon: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    songId.isNotEmpty &&
                            QueueService.instance.hasNext &&
                            !_isPageChanging
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                    BlendMode.srcIn,
                  ),
                  child: Icon(Icons.skip_next, size: iconSize),
                ),
              ),
            ],
          ),
        ),

        // Right side: Shuffle button
        ListenableBuilder(
          listenable: QueueService.instance,
          builder: (context, _) {
            final queueLength = QueueService.instance.queue.length;
            final canShuffle = queueLength >= 3;
            final isShuffled = QueueService.instance.shuffleEnabled;

            return IconButton(
              onPressed: canShuffle
                  ? () async {
                      await QueueService.instance.toggleShuffle();
                      StatusMessageController.instance.showMessage(
                        QueueService.instance.shuffleEnabled
                            ? 'Shuffle on'
                            : 'Shuffle off',
                        duration: const Duration(milliseconds: 1200),
                      );
                    }
                  : null,
              icon: Icon(
                Icons.shuffle,
                color: canShuffle
                    ? (isShuffled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface)
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                size: iconSize,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSongContent(
    Map<String, dynamic>? row,
    String songId,
    double screenWidth,
    double screenHeight,
  ) {
    // Calculate responsive sizes
    final albumArtSize = screenWidth * 0.85;
    final topSpacing = screenHeight * 0.05;
    final albumArtSpacing = screenHeight * 0.03;

    if (row == null) {
      final primary = Theme.of(context).colorScheme.primary;
      return Column(
        children: [
          SizedBox(height: topSpacing),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: albumArtSize * 0.8,
              height: albumArtSize * 0.8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimateGradient(
                    primaryColors: [
                      primary,
                      primary.withValues(alpha: 1),
                      primary.withValues(alpha: .7),
                    ],
                    secondaryColors: [
                      primary,
                      primary.withValues(alpha: .4),
                      primary.withValues(alpha: .1),
                    ],
                  ),
                  Center(
                    child: Icon(
                      Icons.music_note,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: albumArtSpacing),
          Text(
            'No Song Playing',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
            ),
          ),
        ],
      );
    }

    final title = (row['title'] as String?) ?? 'Unknown Title';
    final artists = (row['artists'] as String?) ?? 'Unknown Artist';
    final durationMs = row['duration_ms'] as int?;

    return Column(
      children: [
        SizedBox(height: topSpacing),
        // Album art with 3-dot menu overlay
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Stack(
            children: [
              AlbumArtWidget(
                songId: songId,
                width: albumArtSize,
                height: albumArtSize,
                borderRadius: BorderRadius.circular(screenWidth * 0.031),
              ),
              // 3-dot menu on top right corner
              Positioned(
                top: screenWidth * 0.021,
                right: screenWidth * 0.021,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: screenWidth * 0.0625,
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) async {
                      if (songId.isEmpty) return;

                      switch (value) {
                        case 'toggle_liked':
                          final newStatus =
                              await LikedSongsHelper.toggleLikedStatus(songId);
                          // Reload song data to update the menu icon
                          await _loadAllSongData();
                          if (mounted) {
                            StatusMessageController.instance.showMessage(
                              newStatus
                                  ? 'Added to Liked Songs'
                                  : 'Removed from Liked Songs',
                              duration: const Duration(milliseconds: 1200),
                            );
                          }
                          break;
                        case 'add_to_playlist':
                          final ctx = context;
                          String? songTitle;
                          try {
                            final song = await DatabaseHelper.instance.getSong(
                              songId,
                            );
                            songTitle = song?['title'] as String?;
                          } catch (e) {
                            debugPrint('Error getting song title: $e');
                          }
                          if (!ctx.mounted) return;
                          showAddToPlaylistBottomSheet(
                            ctx,
                            songId,
                            songTitle: songTitle,
                          );
                          break;
                        case 'save_to_disk':
                          final savedContext = context;
                          final song = await DatabaseHelper.instance.getSong(
                            songId,
                          );
                          if (song != null && savedContext.mounted) {
                            final isDeviceFile =
                                song['source'] == 'device' ||
                                song['is_device_file'] == 'true';
                            final isOffline =
                                song['on_device_status'] == 'true' &&
                                song['on_device_filename'] != null &&
                                (song['on_device_filename'] as String)
                                    .isNotEmpty;
                            if (!isDeviceFile && isOffline) {
                              SaveToDiskHelper.saveToDisk(
                                context: savedContext,
                                songId: songId,
                                sourceFilePath:
                                    song['on_device_filename'] as String?,
                                songTitle: song['title'] as String?,
                                artistName: song['artists'] as String?,
                              );
                            } else {
                              StatusMessageController.instance.showMessage(
                                'Song not available offline',
                                duration: const Duration(milliseconds: 2000),
                              );
                            }
                          }
                          break;
                        case 'go_to_album':
                        case 'go_to_artist':
                          await MusicNavigationHelper.handleNavigationMenuSelection(
                            context,
                            value,
                            songId,
                          );
                          break;
                        case 'remove_from_library':
                          final song = await DatabaseHelper.instance.getSong(
                            songId,
                          );
                          if (song != null) {
                            final isDeviceFile =
                                song['source'] == 'device' ||
                                song['is_device_file'] == 'true';
                            if (!isDeviceFile && mounted) {
                              await MusicNavigationHelper.removeFromLibrary(
                                context,
                                songId,
                                song['title'] as String?,
                              );
                            }
                          }
                          break;
                        case 'download_auto':
                          // Auto download using priority order
                          final dlSong = await DatabaseHelper.instance.getSong(
                            songId,
                          );
                          final dlTitle = dlSong?['title'] as String?;
                          final dlIsOffline =
                              dlSong?['on_device_status'] == 'true' &&
                              dlSong?['on_device_filename'] != null &&
                              (dlSong?['on_device_filename'] as String)
                                  .isNotEmpty;
                          if (dlIsOffline) {
                            await DownloadMenuHelper.redownloadSongAuto(
                              songId,
                              songTitle: dlTitle,
                            );
                          } else {
                            await DownloadMenuHelper.downloadSongAuto(
                              songId,
                              songTitle: dlTitle,
                            );
                          }
                          _loadAllSongData();
                          break;
                        case 'download_choose_method':
                          // Show method selection dialog
                          final dlContext = context;
                          if (!dlContext.mounted) return;
                          final method =
                              await DownloadMenuHelper.showMethodSelectionDialog(
                                dlContext,
                              );
                          if (method != null) {
                            final song = await DatabaseHelper.instance.getSong(
                              songId,
                            );
                            final songTitle = song?['title'] as String?;
                            final isOffline =
                                song?['on_device_status'] == 'true' &&
                                song?['on_device_filename'] != null &&
                                (song?['on_device_filename'] as String)
                                    .isNotEmpty;
                            if (isOffline) {
                              await DownloadMenuHelper.redownloadSongWithMethod(
                                songId,
                                method,
                                songTitle: songTitle,
                              );
                            } else {
                              await DownloadMenuHelper.downloadSongWithMethod(
                                songId,
                                method,
                                songTitle: songTitle,
                              );
                            }
                            _loadAllSongData();
                          }
                          break;
                      }
                    },
                    itemBuilder: (context) {
                      // Check if song is available for saving to disk
                      final songData = _currentSongData;
                      final isDeviceFile =
                          songData?['source'] == 'device' ||
                          songData?['is_device_file'] == 'true';
                      final isOfflineAvailable =
                          !isDeviceFile &&
                          songData?['on_device_status'] == 'true' &&
                          songData?['on_device_filename'] != null &&
                          (songData?['on_device_filename'] as String?)
                                  ?.isNotEmpty ==
                              true;

                      // Check if song is liked
                      final isLiked = songData?['liked_status'] == 'true';

                      return [
                        PopupMenuItem<String>(
                          value: 'toggle_liked',
                          child: Row(
                            children: [
                              Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isLiked ? 'Remove from Liked' : 'Add to Liked',
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'add_to_playlist',
                          child: Row(
                            children: [
                              Icon(Icons.playlist_add),
                              SizedBox(width: 12),
                              Text('Add to playlist'),
                            ],
                          ),
                        ),
                        if (isOfflineAvailable)
                          const PopupMenuItem<String>(
                            value: 'save_to_disk',
                            child: Row(
                              children: [
                                Icon(Icons.save_alt),
                                SizedBox(width: 12),
                                Text('Save to disk'),
                              ],
                            ),
                          ),
                        // Download / Redownload option (not for device files)
                        if (!isDeviceFile)
                          PopupMenuItem<String>(
                            value: 'download_auto',
                            child: Row(
                              children: [
                                Icon(
                                  isOfflineAvailable
                                      ? Icons.refresh
                                      : Icons.download,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  isOfflineAvailable
                                      ? 'Redownload'
                                      : 'Download',
                                ),
                              ],
                            ),
                          ),
                        if (!isDeviceFile)
                          const PopupMenuItem<String>(
                            value: 'download_choose_method',
                            child: Row(
                              children: [
                                Icon(Icons.settings, size: 22),
                                SizedBox(width: 12),
                                Text('Choose Method'),
                              ],
                            ),
                          ),
                        if (!isDeviceFile)
                          const PopupMenuItem<String>(
                            value: 'remove_from_library',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red),
                                SizedBox(width: 12),
                                Text(
                                  'Remove from Library',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ...MusicNavigationHelper.createNavigationMenuItems(
                          context,
                          songId,
                        ),
                      ];
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: albumArtSpacing),
        // Title and Artist - ALWAYS CENTERED with auto-scrolling
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.156),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title - Auto-scrolling horizontally
              AutoScrollText(
                text: title,
                style: Theme.of(context).textTheme.titleLarge,
                scrollDuration: const Duration(seconds: 5),
                pauseDuration: const Duration(milliseconds: 1500),
              ),
              SizedBox(height: screenHeight * 0.005),
              // Artists - Auto-scrolling and clickable
              GestureDetector(
                onTap: songId.isNotEmpty && artists != 'Unknown Artist'
                    ? () async {
                        await MusicNavigationHelper.goToArtist(context, songId);
                      }
                    : null,
                child: AutoScrollText(
                  text: artists,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  scrollDuration: const Duration(seconds: 4),
                  pauseDuration: const Duration(milliseconds: 1500),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        // Progress slider
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.026),
          child: Column(
            children: [
              StreamBuilder<Duration>(
                stream: pc.positionStream,
                builder: (context, posSnapshot) {
                  return StreamBuilder<Duration?>(
                    stream: pc.durationStream,
                    builder: (context, durSnapshot) {
                      final isLoading = pc.mode == PlaybackMode.loading;
                      final isError = pc.mode == PlaybackMode.error;
                      final isDisabled = isLoading || isError;
                      final position = isDisabled
                          ? Duration.zero
                          : (posSnapshot.data ?? Duration.zero);
                      final duration = isDisabled
                          ? Duration.zero
                          : (durSnapshot.data ??
                                (durationMs != null
                                    ? Duration(milliseconds: durationMs)
                                    : Duration.zero));
                      final value = duration.inMilliseconds > 0
                          ? position.inMilliseconds / duration.inMilliseconds
                          : 0.0;
                      return Slider(
                        value: value.clamp(0.0, 1.0),
                        onChanged: isDisabled
                            ? null
                            : (v) {
                                if (duration.inMilliseconds > 0) {
                                  final newPosition = Duration(
                                    milliseconds: (v * duration.inMilliseconds)
                                        .round(),
                                  );
                                  pc.seek(newPosition);
                                }
                              },
                        activeColor: isDisabled
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.3)
                            : Theme.of(context).colorScheme.primary,
                        inactiveColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.2),
                      );
                    },
                  );
                },
              ),
              // Time labels
              StreamBuilder<Duration>(
                stream: pc.positionStream,
                builder: (context, posSnapshot) {
                  return StreamBuilder<Duration?>(
                    stream: pc.durationStream,
                    builder: (context, durSnapshot) {
                      final isLoading = pc.mode == PlaybackMode.loading;
                      final isError = pc.mode == PlaybackMode.error;
                      final isDisabled = isLoading || isError;
                      final position = isDisabled
                          ? Duration.zero
                          : (posSnapshot.data ?? Duration.zero);
                      final duration = isDisabled
                          ? Duration.zero
                          : (durSnapshot.data ??
                                (durationMs != null
                                    ? Duration(milliseconds: durationMs)
                                    : Duration.zero));
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.065,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
      ],
    );
  }

  /// Build sync/login status icon
  /// Shows login icon if not logged in, sync status if logged in
  /// Clicking shows auth dialog or triggers manual sync
  Widget _buildSyncStatusIcon(BuildContext context, {double size = 20}) {
    // Check if user is logged in
    final isLoggedIn = AuthService.instance.isLoggedIn;

    if (!isLoggedIn) {
      // Show login icon when not logged in
      return GestureDetector(
        onTap: () {
          // Show login/signup bottom sheet
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: AuthWidget(
                  onLoginSuccess: () {
                    // Close bottom sheet and refresh UI
                    Navigator.of(context).pop();
                    setState(() {});
                    StatusMessageController.instance.showMessage(
                      'Successfully logged in',
                      duration: const Duration(milliseconds: 2200),
                    );
                  },
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(
            Icons.login,
            color: Theme.of(context).colorScheme.primary,
            size: size,
          ),
        ),
      );
    }

    // User is logged in - show sync status
    return StreamBuilder<bool>(
      stream: syncService.syncStatusStream,
      initialData: syncService.isSyncing,
      builder: (context, snapshot) {
        final isSyncing = snapshot.data ?? false;

        return GestureDetector(
          onTap: isSyncing
              ? null
              : () async {
                  // Manual sync trigger
                  try {
                    await syncService.syncData();
                    if (context.mounted) {
                      StatusMessageController.instance.showMessage(
                        'Backup synced successfully',
                        duration: const Duration(milliseconds: 2200),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      StatusMessageController.instance.showMessage(
                        'Sync failed: ${e.toString()}',
                        duration: const Duration(milliseconds: 2500),
                      );
                    }
                  }
                },
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: SizedBox(
              width: size,
              height: size,
              child: isSyncing
                  ? LoadingAnimationWidget.staggeredDotsWave(
                      color: Theme.of(context).colorScheme.primary,
                      size: size,
                    )
                  : Icon(
                      Icons.cloud_done,
                      color: Theme.of(context).colorScheme.primary,
                      size: size,
                    ),
            ),
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final totalSecs = duration.inSeconds;
    final minutes = totalSecs ~/ 60;
    final seconds = totalSecs % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
