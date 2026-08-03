import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import '../../data/database_helper.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/status_message_controller.dart';
import '../../services/download_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/download_menu_helper.dart';
import 'album_art_widget.dart';

/// Global key to access RecentWheel from other widgets
final GlobalKey<_RecentWheelState> _recentWheelKey =
    GlobalKey<_RecentWheelState>();

class RecentWheel extends StatefulWidget {
  RecentWheel() : super(key: _recentWheelKey);

  @override
  State<RecentWheel> createState() => _RecentWheelState();
}

/// Static method to refresh recent wheel from external widgets
class RecentWheelController {
  static Future<void> refresh() async {
    await _recentWheelKey.currentState?.refresh();
  }
}

class _RecentWheelState extends State<RecentWheel> {
  List<Map<String, dynamic>> _recentSongs = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    _loadRecentSongs();
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
    final hasThisSong = _recentSongs.any((s) => s['id']?.toString() == songId);
    if (hasThisSong && mounted) {
      _loadRecentSongs();
    }
  }

  /// Public method to refresh recent songs from external widgets
  Future<void> refresh() async {
    await _loadRecentSongs();
  }

  Future<void> _loadRecentSongs() async {
    try {
      final recentSongs = await DatabaseHelper.instance.getRecentSongs(
        limit: 10,
      );
      debugPrint('RecentWheel: Loaded ${recentSongs.length} recent songs');

      if (mounted) {
        setState(() {
          _recentSongs = recentSongs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('RecentWheel: Error loading recent songs: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onTapPlay(Map<String, dynamic> song) async {
    try {
      final songId = song['id']?.toString();
      final title = song['title']?.toString() ?? 'Unknown';

      if (songId != null) {
        final currentSongId = SimplePlaybackController.instance.currentSongId;

        // Check if this exact song is already playing
        final isExactSamePlayback = currentSongId == songId;

        if (isExactSamePlayback) {
          // Same song - toggle play/pause
          if (SimplePlaybackController.instance.isPlaying) {
            debugPrint('RecentWheel: Pausing currently playing song $songId');
            await SimplePlaybackController.instance.pause();
          } else {
            debugPrint('RecentWheel: Resuming paused song $songId');
            await SimplePlaybackController.instance.resume();
          }
        } else {
          // Different song - set new queue and play
          debugPrint('RecentWheel: Playing song $songId from recent');

          await QueueService.instance.setQueue(
            [songId],
            startIndex: 0,
            context: PlaybackContext.song,
            contextId: songId,
          );
          await SimplePlaybackController.instance.play(songId, null);

          debugPrint('RecentWheel: Started playing $title');
        }
      }
    } catch (e) {
      debugPrint('RecentWheel: Error playing song: $e');
      StatusMessageController.instance.showMessage(
        'Error playing song',
        duration: const Duration(milliseconds: 2000),
      );
    }
  }

  Future<void> _removeFromRecents(String songId, String title) async {
    try {
      await DatabaseHelper.instance.removeRecentSong(songId);
      await _loadRecentSongs();
      StatusMessageController.instance.showMessage(
        'Removed "$title" from recents',
        duration: const Duration(milliseconds: 2200),
      );
    } catch (e) {
      debugPrint('RecentWheel: Error removing from recents: $e');
      StatusMessageController.instance.showMessage(
        'Failed to remove from recents',
        duration: const Duration(milliseconds: 2200),
      );
    }
  }

  /// Build the play indicator (visualizer, loading, error, or pause icon)
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

    if (_recentSongs.isEmpty) {
      return const SizedBox(
        height: 185,
        child: Center(
          child: Text(
            'No recent plays yet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return SizedBox(
      height: 180, // Match MostPlayedWheel height exactly
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
            itemCount: _recentSongs.length,
            itemBuilder: (context, index) {
              final song = _recentSongs[index];
              final songId = song['id']?.toString() ?? '';
              final title = song['title']?.toString() ?? 'Unknown';

              return GestureDetector(
                onTap: () => _onTapPlay(song),
                child: Container(
                  width: 130, // Match MostPlayedWheel width exactly
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
                                } else if (value == 'remove_from_recents') {
                                  await _removeFromRecents(songId, title);
                                } else if (value == 'remove_from_library') {
                                  final isDeviceFile =
                                      song['source'] == 'device' ||
                                      song['is_device_file'] == 'true';
                                  if (!isDeviceFile) {
                                    await MusicNavigationHelper.removeFromLibrary(
                                      context,
                                      songId,
                                      title,
                                      onRemoved: () => _loadRecentSongs(),
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
                                  _loadRecentSongs();
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
                                    _loadRecentSongs();
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
                                    value: 'remove_from_recents',
                                    child: Text('Remove from Recents'),
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
                      const SizedBox(
                        height: 10,
                      ), // Match MostPlayedWheel spacing
                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12, // Match MostPlayedWheel font size
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2, // Match MostPlayedWheel maxLines
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
