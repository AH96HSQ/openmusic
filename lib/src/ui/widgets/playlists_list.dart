import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:animate_gradient/animate_gradient.dart';
import '../../services/status_message_controller.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import '../../services/playlists_service.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../helpers/download_menu_helper.dart';
import '../../data/database_helper.dart';
import 'playlist_art_widget.dart';
import '../pages/add_to_playlist_bottom_sheet.dart';

class PlaylistsList extends StatefulWidget {
  final Function(String playlistId, String playlistName)? onPlaylistTap;

  const PlaylistsList({super.key, this.onPlaylistTap});

  @override
  State<PlaylistsList> createState() => _PlaylistsListState();
}

class _PlaylistsListState extends State<PlaylistsList>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlaylists();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh playlists when app comes back to foreground
      _refreshIfNeeded();
    }
  }

  void _refreshIfNeeded() {
    final now = DateTime.now();
    if (_lastRefresh == null || now.difference(_lastRefresh!).inSeconds > 2) {
      _loadPlaylists();
    }
  }

  Future<void> _loadPlaylists() async {
    try {
      final playlists = await PlaylistsService.getAllPlaylists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('PlaylistsGrid: Error loading playlists: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    }
  }

  Future<void> _showCreatePlaylistDialog() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreatePlaylistBottomSheet(),
    );

    if (result != null && result.isNotEmpty) {
      _loadPlaylists(); // Refresh the list
      // Success message is handled by the bottom sheet
    }
  }

  Future<void> _handleMenuAction(
    String action,
    String playlistId,
    String playlistName,
  ) async {
    switch (action) {
      case 'queue':
        try {
          debugPrint('Queue up playlist: $playlistName');

          // Get all songs from the playlist
          final songs = await PlaylistsService.getPlaylistSongs(playlistId);
          if (songs.isEmpty) {
            StatusMessageController.instance.showMessage(
              'Playlist "$playlistName" is empty',
              duration: const Duration(milliseconds: 2200),
            );
            return;
          }

          // Add all songs to the queue
          for (final songId in songs) {
            await QueueService.instance.addToQueue(songId);
          }

          StatusMessageController.instance.showMessage(
            'Added ${songs.length} song${songs.length == 1 ? '' : 's'} from "$playlistName" to queue',
            duration: const Duration(milliseconds: 2200),
          );
        } catch (e) {
          debugPrint('Error queueing playlist: $e');
          StatusMessageController.instance.showMessage(
            'Failed to add playlist to queue',
            duration: const Duration(milliseconds: 2200),
          );
        }
        break;
      case 'delete':
        await _deletePlaylist(playlistId, playlistName);
        break;
      case 'download_all':
        await _downloadAllSongsInPlaylist(playlistId, playlistName);
        break;
    }
  }

  /// Download all songs in a playlist
  Future<void> _downloadAllSongsInPlaylist(
    String playlistId,
    String playlistName,
  ) async {
    try {
      // Get all songs from the playlist
      final songIds = await PlaylistsService.getPlaylistSongs(playlistId);
      if (songIds.isEmpty) {
        StatusMessageController.instance.showMessage(
          'Playlist "$playlistName" is empty',
          duration: const Duration(milliseconds: 1500),
        );
        return;
      }

      // Filter out device files and already downloaded songs
      final songsToDownload = <String>[];
      for (final songId in songIds) {
        final song = await DatabaseHelper.instance.getSong(songId);
        if (song == null) continue;

        final isDeviceFile =
            song['source'] == 'device' || song['is_device_file'] == 'true';
        if (isDeviceFile) continue;

        final isAlreadyDownloaded =
            song['on_device_status'] == 'true' &&
            song['on_device_filename'] != null &&
            (song['on_device_filename'] as String).isNotEmpty;
        if (isAlreadyDownloaded) continue;

        songsToDownload.add(songId);
      }

      if (songsToDownload.isEmpty) {
        StatusMessageController.instance.showMessage(
          'All songs already downloaded',
          duration: const Duration(milliseconds: 1500),
        );
        return;
      }

      // Queue all songs for download
      DownloadMenuHelper.downloadMultipleSongs(songsToDownload);
    } catch (e) {
      debugPrint('Error downloading playlist songs: $e');
      StatusMessageController.instance.showMessage(
        'Failed to start downloads',
        duration: const Duration(milliseconds: 1500),
      );
    }
  }

  Future<void> _deletePlaylist(String playlistId, String playlistName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text(
          'Are you sure you want to delete "$playlistName"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await PlaylistsService.deletePlaylist(playlistId);
        _loadPlaylists(); // Refresh the list
        if (mounted) {
          StatusMessageController.instance.showMessage(
            'Deleted playlist "$playlistName"',
            duration: const Duration(milliseconds: 1200),
          );
        }
      } catch (e) {
        if (mounted) {
          StatusMessageController.instance.showMessage(
            'Failed to delete playlist: $e',
            duration: const Duration(milliseconds: 1800),
          );
        }
      }
    }
  }

  Widget _buildPlaylistTile(Map<String, dynamic> playlist) {
    final playlistId = playlist['id'] as String;
    final name = playlist['name'] as String;
    final songCount = playlist['songCount'] as int? ?? 0;
    final topSongIds =
        (playlist['topSongIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    final isDefault = playlist['isDefault'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          widget.onPlaylistTap?.call(playlistId, name);
        },
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          child: Row(
            children: [
              // Thumbnail - fixed 70x70 square with separate tap handler
              GestureDetector(
                onTap: () => _onPlaylistArtTap(playlistId, name),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: _buildThumbnail(playlistId, topSongIds, isDefault),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$songCount songs',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Playback indicator (appears when this playlist is being played)
              _PlaylistPlaybackIndicator(playlistId: playlistId),

              const SizedBox(width: 8),

              // Menu icon
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) =>
                    _handleMenuAction(value, playlistId, name),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'queue',
                    child: Row(
                      children: [
                        Icon(Icons.queue_music),
                        SizedBox(width: 12),
                        Text('Queue up'),
                      ],
                    ),
                  ),
                  // Download All - only for non-device-files playlists
                  if (playlistId != PlaylistsService.deviceFilesId)
                    const PopupMenuItem(
                      value: 'download_all',
                      child: Row(
                        children: [
                          Icon(Icons.download),
                          SizedBox(width: 12),
                          Text('Download All'),
                        ],
                      ),
                    ),
                  if (!isDefault)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle tapping on playlist album art - play playlist and add to recents
  Future<void> _onPlaylistArtTap(String playlistId, String playlistName) async {
    try {
      debugPrint('PlaylistsList: Playing playlist $playlistId ($playlistName)');

      // Get all songs from the playlist
      final songs = await PlaylistsService.getPlaylistSongs(playlistId);
      if (songs.isEmpty) {
        debugPrint('PlaylistsList: Playlist $playlistId is empty, cannot play');
        return;
      }

      // Check if this playlist is already playing
      final currentContext = QueueService.instance.playbackContext;
      final currentContextId = QueueService.instance.playbackContextId;
      final firstSongId = songs.first;
      final isAlreadyPlayingThisPlaylist =
          currentContext == PlaybackContext.playlist &&
          currentContextId == playlistId &&
          SimplePlaybackController.instance.currentSongId == firstSongId;

      debugPrint(
        'PlaylistsList: Context check - currentContext: $currentContext, currentContextId: $currentContextId, currentSongId: ${SimplePlaybackController.instance.currentSongId}',
      );
      debugPrint(
        'PlaylistsList: This playlistId: $playlistId, firstSongId: $firstSongId',
      );
      debugPrint(
        'PlaylistsList: isAlreadyPlayingThisPlaylist: $isAlreadyPlayingThisPlaylist',
      );

      if (isAlreadyPlayingThisPlaylist) {
        // This exact playlist is already playing - just toggle play/pause
        if (SimplePlaybackController.instance.isPlaying) {
          await SimplePlaybackController.instance.pause();
        } else {
          await SimplePlaybackController.instance.resume();
        }
      } else {
        // Different playlist or different context - set new queue and play
        await QueueService.instance.setQueue(
          songs,
          startIndex: 0,
          context: PlaybackContext.playlist,
          contextId: playlistId,
        );

        // Play count will be automatically tracked by SimplePlaybackController for individual songs

        await SimplePlaybackController.instance.play(firstSongId, null);
      }

      debugPrint(
        'PlaylistsList: Started playing playlist $playlistName with ${songs.length} songs',
      );
    } catch (e) {
      debugPrint('PlaylistsList: Error playing playlist $playlistId: $e');
    }
  }

  Widget _buildThumbnail(
    String playlistId,
    List<String> topSongIds,
    bool isDefault,
  ) {
    if (topSongIds.isNotEmpty) {
      // Use PlaylistArtWidget to show collage or single art
      return PlaylistArtWidget(topSongIds: topSongIds, width: 70, height: 70);
    }

    // Default icons for empty playlists
    IconData iconData;

    switch (playlistId) {
      case PlaylistsService.likedSongsId:
        iconData = Icons.favorite_border;
        break;
      case PlaylistsService.offlineSongsId:
        iconData = Icons.download_outlined;
        break;
      case PlaylistsService.deviceFilesId:
        iconData = Icons.phone_android_outlined;
        break;
      default:
        iconData = Icons.queue_music_outlined;
        break;
    }

    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimateGradient(
            primaryColors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: 1),
              Theme.of(context).colorScheme.primary.withValues(alpha: .7),
            ],
            secondaryColors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: .4),
              Theme.of(context).colorScheme.primary.withValues(alpha: .1),
            ],
          ),
          Center(child: Icon(iconData, size: 40, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildAddPlaylistTile() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: _showCreatePlaylistDialog,
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          child: Row(
            children: [
              // Thumbnail - fixed 70x70 square with gradient
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimateGradient(
                        primaryColors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 1),
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .7),
                        ],
                        secondaryColors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .4),
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .1),
                        ],
                      ),
                      Center(
                        child: Icon(
                          Icons.add_outlined,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Create Playlist',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add a new playlist',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        // Playlist tiles
        ...(_playlists.map((playlist) => _buildPlaylistTile(playlist))),

        // Add Playlist tile at the bottom
        _buildAddPlaylistTile(),
      ],
    );
  }
}

/// Playback indicator for playlist tiles (shows when playlist is currently playing)
class _PlaylistPlaybackIndicator extends StatefulWidget {
  final String playlistId;
  const _PlaylistPlaybackIndicator({required this.playlistId});

  @override
  State<_PlaylistPlaybackIndicator> createState() =>
      _PlaylistPlaybackIndicatorState();
}

class _PlaylistPlaybackIndicatorState
    extends State<_PlaylistPlaybackIndicator> {
  final pc = SimplePlaybackController.instance;
  final qs = QueueService.instance;

  @override
  void initState() {
    super.initState();
    pc.addListener(_onStateChange);
    qs.addListener(_onStateChange);
  }

  @override
  void dispose() {
    pc.removeListener(_onStateChange);
    qs.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() => setState(() {});

  /// Check if this specific playlist should show indicators based on playback context
  bool _shouldShowPlaylistIndicator() {
    if (pc.currentSongId == null) return false;

    // Use the context-aware method from QueueService
    return QueueService.instance.shouldShowPlaylistIndicator(widget.playlistId);
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowIndicator = _shouldShowPlaylistIndicator();

    if (!shouldShowIndicator) {
      // Not the current playlist context - show nothing
      return const SizedBox.shrink();
    }

    // Use StreamBuilder to listen to player state changes
    return SizedBox(
      width: 24,
      height: 24,
      child: StreamBuilder<PlayerState>(
        stream: pc.playerStateStream,
        builder: (context, snapshot) {
          return _buildIndicator(snapshot.data);
        },
      ),
    );
  }

  Widget _buildIndicator(PlayerState? playerState) {
    final isLoading = pc.mode == PlaybackMode.loading;
    final isError =
        pc.mode == PlaybackMode.error && pc.lastErrorSongId == pc.currentSongId;
    final isPlaying =
        playerState?.playing == true &&
        (pc.mode == PlaybackMode.streaming || pc.mode == PlaybackMode.file);

    // Show error icon when download failed for the current song in this playlist
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
}
