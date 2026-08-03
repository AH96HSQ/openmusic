import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import '../../services/most_played_service.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/status_message_controller.dart';
import '../../services/download_helper.dart';
import '../../data/database_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/download_menu_helper.dart';
import 'album_art_widget.dart';

/// Global key to access MostPlayedWheel from other widgets
final GlobalKey<_MostPlayedWheelState> _mostPlayedWheelKey =
    GlobalKey<_MostPlayedWheelState>();

class MostPlayedWheel extends StatefulWidget {
  MostPlayedWheel() : super(key: _mostPlayedWheelKey);

  @override
  State<MostPlayedWheel> createState() => _MostPlayedWheelState();
}

/// Static method to refresh most played from external widgets
class MostPlayedWheelController {
  static Future<void> refresh() async {
    await _mostPlayedWheelKey.currentState?.refresh();
  }
}

class _MostPlayedWheelState extends State<MostPlayedWheel> {
  List<Map<String, dynamic>> _mostPlayedSongs = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  /// Format play time in seconds to total minutes only
  String _formatPlayTime(int seconds) {
    final minutes = (seconds / 60).round();
    return '${minutes}m';
  }

  @override
  void initState() {
    super.initState();
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    _loadMostPlayedSongs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    super.dispose();
  }

  /// Called when a download completes - refresh to update menu options
  void _onDownloadComplete(String songId) {
    // Check if this song is in our list and refresh if so
    final hasThisSong = _mostPlayedSongs.any(
      (s) => s['id']?.toString() == songId,
    );
    if (hasThisSong && mounted) {
      _loadMostPlayedSongs();
    }
  }

  /// Public method to refresh most played from external widgets
  Future<void> refresh() async {
    await _loadMostPlayedSongs();
  }

  Future<void> _loadMostPlayedSongs() async {
    try {
      final mostPlayedSongs = await MostPlayedService.getMostPlayedSongs(
        limit: 10,
      );
      debugPrint(
        'MostPlayedWheel: Raw most played count: ${mostPlayedSongs.length}',
      );

      // Filter out entries with invalid song IDs
      final validMostPlayedSongs = mostPlayedSongs.where((song) {
        final songId = song['id'];
        debugPrint(
          'MostPlayedWheel: Checking song - songId: $songId, title: ${song['title']}',
        );

        if (songId == null) {
          debugPrint(
            'MostPlayedWheel: Filtering out null songId for ${song['title']}',
          );
          return false;
        }

        final songIdStr = songId.toString();
        // Skip temporary IDs that start with "temp_"
        if (songIdStr.startsWith('temp_')) {
          debugPrint('MostPlayedWheel: Filtering out temp ID: $songIdStr');
          return false;
        }

        debugPrint('MostPlayedWheel: Keeping song with songId: $songIdStr');
        return true;
      }).toList();

      debugPrint(
        'MostPlayedWheel: Valid most played songs count: ${validMostPlayedSongs.length}',
      );

      if (mounted) {
        setState(() {
          _mostPlayedSongs = validMostPlayedSongs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MostPlayedWheel: Error loading most played songs: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPlayHistory(String songId, String title) async {
    // Show confirmation bottom sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reset History',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Are you sure you want to reset the history for "$title"?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'This will set the play time and play count to 0.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // Reset play history in database
      await DatabaseHelper.instance.resetPlayHistory(songId);

      // Reload the most played songs list
      await _loadMostPlayedSongs();

      StatusMessageController.instance.showMessage(
        'Reset play history for "$title"',
        duration: const Duration(milliseconds: 2200),
      );
    } catch (e) {
      debugPrint('MostPlayedWheel: Error resetting play history: $e');
      StatusMessageController.instance.showMessage(
        'Failed to reset play history',
        duration: const Duration(milliseconds: 2200),
      );
    }
  }

  Future<void> _onTapPlay(Map<String, dynamic> song) async {
    try {
      final songId = song['id']?.toString();
      final title = song['title']?.toString() ?? '';

      if (songId != null) {
        final currentSongId = SimplePlaybackController.instance.currentSongId;
        final currentContext = QueueService.instance.playbackContext;
        final currentContextId = QueueService.instance.playbackContextId;

        // Check if this exact song in this exact context is already playing
        final isExactSamePlayback =
            currentContext == PlaybackContext.mostPlayed &&
            currentContextId == songId &&
            currentSongId == songId;

        if (isExactSamePlayback) {
          // Same song in same context - toggle play/pause
          if (SimplePlaybackController.instance.isPlaying) {
            debugPrint(
              'MostPlayedWheel: Pausing currently playing song $songId',
            );
            await SimplePlaybackController.instance.pause();
          } else {
            debugPrint('MostPlayedWheel: Resuming paused song $songId');
            await SimplePlaybackController.instance.resume();
          }
        } else {
          // Different song or different context - set new queue and play
          debugPrint('MostPlayedWheel: Playing song $songId from most played');

          await QueueService.instance.setQueue(
            [songId],
            startIndex: 0,
            context: PlaybackContext.mostPlayed,
            contextId: songId,
          );
          await SimplePlaybackController.instance.play(songId, null);

          debugPrint(
            'MostPlayedWheel: Recorded replay of $title to move to top',
          );
        }
      }
    } catch (e) {
      debugPrint('MostPlayedWheel: Error playing song: $e');
    }
  }

  Widget _buildPlayIndicator(PlayerState? playerState, String songId) {
    final pc = SimplePlaybackController.instance;
    final isLoading = pc.mode == PlaybackMode.loading;
    final isError =
        pc.mode == PlaybackMode.error && pc.lastErrorSongId == songId;
    final isPlaying =
        playerState?.playing == true &&
        (pc.mode == PlaybackMode.streaming || pc.mode == PlaybackMode.file);

    // Show error icon when download failed for this song
    if (isError) {
      return const Icon(Icons.error_outline, color: Colors.red, size: 20);
    }

    // Only show loading animation when actively loading
    if (isLoading) {
      return LoadingAnimationWidget.threeArchedCircle(
        color: Theme.of(context).colorScheme.primary,
        size: 20,
      );
    }

    if (isPlaying) {
      // Show visualizer when playing
      return MiniMusicVisualizer(
        color: Theme.of(context).colorScheme.primary,
        width: 2,
        height: 12,
        radius: 1,
        animate: true,
      );
    }

    // Show paused indicator when not loading and not playing
    return Icon(
      Icons.pause,
      color: Theme.of(context).colorScheme.primary,
      size: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 185,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mostPlayedSongs.isEmpty) {
      return const SizedBox(
        height: 185,
        child: Center(
          child: Text('No plays yet', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return SizedBox(
      height: 180, // Increased height to accommodate title and artist text
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              // Claim this scroll event so the parent doesn't also scroll
              GestureBinding.instance.pointerSignalResolver.register(
                pointerSignal,
                (event) {
                  final offset =
                      _scrollController.offset +
                      (event as PointerScrollEvent).scrollDelta.dy;
                  _scrollController.jumpTo(
                    offset.clamp(
                      0.0,
                      _scrollController.position.maxScrollExtent,
                    ),
                  );
                },
              );
            }
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 0),
            itemCount: _mostPlayedSongs.length,
            itemBuilder: (context, index) {
              final song = _mostPlayedSongs[index];
              final songId = song['id']?.toString() ?? '';
              final title = song['title']?.toString() ?? 'Unknown Title';
              final playTime = song['play_time'] ?? 0;

              return GestureDetector(
                onTap: () => _onTapPlay(song),
                child: Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Album art container with play indicator and menu
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AlbumArtWidget(
                              songId: songId,
                              width: 130,
                              height: 130,
                              autoDownload: false,
                            ),
                          ),
                          // 3-dot menu in top right
                          Positioned(
                            top: 0,
                            right: 0,
                            child: PopupMenuButton<String>(
                              color: Theme.of(context).colorScheme.surface,
                              icon: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              onSelected: (value) async {
                                if (value == 'play_next') {
                                  await QueueService.instance.playNext(songId);
                                  StatusMessageController.instance.showMessage(
                                    'Will play "$title" next',
                                    duration: const Duration(
                                      milliseconds: 2200,
                                    ),
                                  );
                                } else if (value == 'add_to_queue') {
                                  await QueueService.instance.addToQueue(
                                    songId,
                                  );
                                  StatusMessageController.instance.showMessage(
                                    'Added "$title" to queue',
                                    duration: const Duration(
                                      milliseconds: 2200,
                                    ),
                                  );
                                } else if (value == 'reset_history') {
                                  await _resetPlayHistory(songId, title);
                                } else if (value == 'remove_from_library') {
                                  final isDeviceFile =
                                      song['source'] == 'device' ||
                                      song['is_device_file'] == 'true';
                                  if (!isDeviceFile) {
                                    await MusicNavigationHelper.removeFromLibrary(
                                      context,
                                      songId,
                                      title,
                                      onRemoved: () => _loadMostPlayedSongs(),
                                    );
                                  }
                                } else if (value == 'save_to_disk') {
                                  SaveToDiskHelper.saveToDisk(
                                    context: context,
                                    songId: songId,
                                    sourceFilePath:
                                        song['on_device_filename'] as String?,
                                    songTitle: title,
                                    artistName: song['artists'] as String?,
                                  );
                                } else if (value == 'download_auto') {
                                  // Auto download using priority order
                                  if (song['on_device_status'] == 'true' &&
                                      song['on_device_filename'] != null &&
                                      (song['on_device_filename'] as String)
                                          .isNotEmpty) {
                                    await DownloadMenuHelper.redownloadSongAuto(
                                      songId,
                                      songTitle: title,
                                    );
                                  } else {
                                    await DownloadMenuHelper.downloadSongAuto(
                                      songId,
                                      songTitle: title,
                                    );
                                  }
                                  _loadMostPlayedSongs();
                                } else if (value == 'download_choose_method') {
                                  // Show method selection dialog
                                  final method =
                                      await DownloadMenuHelper.showMethodSelectionDialog(
                                        context,
                                      );
                                  if (method != null) {
                                    final isOffline =
                                        song['on_device_status'] == 'true' &&
                                        song['on_device_filename'] != null &&
                                        (song['on_device_filename'] as String)
                                            .isNotEmpty;
                                    if (isOffline) {
                                      await DownloadMenuHelper.redownloadSongWithMethod(
                                        songId,
                                        method,
                                        songTitle: title,
                                      );
                                    } else {
                                      await DownloadMenuHelper.downloadSongWithMethod(
                                        songId,
                                        method,
                                        songTitle: title,
                                      );
                                    }
                                    _loadMostPlayedSongs();
                                  }
                                }
                              },
                              itemBuilder: (ctx) {
                                final isDeviceFile =
                                    song['source'] == 'device' ||
                                    song['is_device_file'] == 'true';
                                final isOfflineAvailable =
                                    !isDeviceFile &&
                                    song['on_device_status'] == 'true' &&
                                    song['on_device_filename'] != null &&
                                    (song['on_device_filename'] as String)
                                        .isNotEmpty;
                                return [
                                  const PopupMenuItem<String>(
                                    value: 'play_next',
                                    child: Text('Play Next'),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'add_to_queue',
                                    child: Text('Queue up'),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'reset_history',
                                    child: Text('Reset History'),
                                  ),
                                  if (!isDeviceFile)
                                    const PopupMenuItem<String>(
                                      value: 'remove_from_library',
                                      child: Text(
                                        'Remove from Library',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  if (isOfflineAvailable)
                                    const PopupMenuItem<String>(
                                      value: 'save_to_disk',
                                      child: Text('Save to disk'),
                                    ),
                                  // Download / Redownload option (not for device files)
                                  if (!isDeviceFile)
                                    PopupMenuItem<String>(
                                      value: 'download_auto',
                                      child: Text(
                                        isOfflineAvailable
                                            ? 'Redownload'
                                            : 'Download',
                                      ),
                                    ),
                                  if (!isDeviceFile)
                                    const PopupMenuItem<String>(
                                      value: 'download_choose_method',
                                      child: Text('Choose Method'),
                                    ),
                                ];
                              },
                            ),
                          ),
                          // Play time badge in bottom right
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _formatPlayTime(playTime),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Currently playing indicator (small, bottom-left corner)
                          StreamBuilder<PlayerState>(
                            stream: SimplePlaybackController
                                .instance
                                .playerStateStream,
                            builder: (context, snapshot) {
                              final playerState = snapshot.data;
                              final currentSongId = SimplePlaybackController
                                  .instance
                                  .currentSongId;
                              final isCurrentlyPlaying =
                                  currentSongId == songId;

                              if (!isCurrentlyPlaying) {
                                return const SizedBox.shrink();
                              }

                              return Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: _buildPlayIndicator(
                                        playerState,
                                        songId,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
