import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:animate_gradient/animate_gradient.dart';
import '../../data/database_helper.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/download_helper.dart';
import '../widgets/song_tile.dart';
import '../widgets/album_art_widget.dart';
import 'add_to_playlist_bottom_sheet.dart';
import '../../helpers/music_navigation_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../../helpers/download_menu_helper.dart';
import '../../services/status_message_controller.dart';

/// Widget that displays songs grouped by album
class AlbumsList extends StatefulWidget {
  const AlbumsList({super.key});

  @override
  State<AlbumsList> createState() => _AlbumsListState();
}

class _AlbumsListState extends State<AlbumsList> with WidgetsBindingObserver {
  Map<String, List<Map<String, dynamic>>> _albumSongs = {};
  List<String> _sortedAlbums = [];
  bool _loading = true;
  DateTime? _lastRefresh;
  String? _expandedAlbum;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DownloadHelper.instance.addDownloadCompleteListener(_onDownloadComplete);
    _loadSongs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DownloadHelper.instance.removeDownloadCompleteListener(_onDownloadComplete);
    super.dispose();
  }

  /// Called when a download completes - refresh to update menu options
  void _onDownloadComplete(String songId) {
    // Refresh all songs since we'd need to check all albums
    if (mounted) {
      _loadSongs();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfNeeded();
    }
  }

  void _refreshIfNeeded() {
    final now = DateTime.now();
    if (_lastRefresh == null || now.difference(_lastRefresh!).inSeconds > 2) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await DatabaseHelper.instance.getAllSongs();

      // Process in isolate to avoid UI jank
      final result = await compute(_groupSongsByAlbum, songs);

      if (mounted) {
        setState(() {
          _albumSongs =
              result['grouped'] as Map<String, List<Map<String, dynamic>>>;
          _sortedAlbums = result['sorted'] as List<String>;
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('AlbumsList: Error loading songs: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _lastRefresh = DateTime.now();
        });
      }
    }
  }

  /// Static function to run in isolate
  static Map<String, dynamic> _groupSongsByAlbum(
    List<Map<String, dynamic>> songs,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final song in songs) {
      final album = (song['album'] as String?)?.trim();
      final albumKey = (album != null && album.isNotEmpty)
          ? album
          : 'Unknown Album';
      grouped.putIfAbsent(albumKey, () => []).add(song);
    }

    final sortedAlbums = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Unknown Album') return 1;
        if (b == 'Unknown Album') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return {'grouped': grouped, 'sorted': sortedAlbums};
  }

  Future<void> _playAlbumSongs(String album, int songIndex) async {
    try {
      final songs = _albumSongs[album] ?? [];
      if (songs.isEmpty) return;

      final songIds = songs.map((s) => s['id'] as String).toList();

      await QueueService.instance.setQueue(
        songIds,
        startIndex: songIndex,
        context: PlaybackContext.playlist,
        contextId: 'album_$album',
      );

      await SimplePlaybackController.instance.play(songIds[songIndex], null);
    } catch (e) {
      debugPrint('AlbumsList: Error playing song: $e');
    }
  }

  List<PopupMenuOption> _getMenuOptions(
    String songId,
    Map<String, dynamic> song,
  ) {
    final songTitle = song['title'] as String?;
    final isDeviceFile =
        song['source'] == 'device' || song['is_device_file'] == 'true';

    return [
      PopupMenuOption(
        id: 'play_next',
        label: 'Play Next',
        onSelected: () async {
          await QueueService.instance.playNext(songId);
          StatusMessageController.instance.showMessage(
            'Will play "${songTitle ?? 'song'}" next',
            duration: const Duration(milliseconds: 2200),
          );
        },
      ),
      PopupMenuOption(
        id: 'add_to_queue',
        label: 'Add to Queue',
        onSelected: () async {
          await QueueService.instance.addToQueue(songId);
          StatusMessageController.instance.showMessage(
            'Added "${songTitle ?? 'song'}" to queue',
            duration: const Duration(milliseconds: 2200),
          );
        },
      ),
      PopupMenuOption(
        id: 'add_to_playlist',
        label: 'Add to playlist',
        onSelected: () async {
          final contextRef = context;
          if (contextRef.mounted) {
            showAddToPlaylistBottomSheet(
              contextRef,
              songId,
              songTitle: songTitle,
            );
          }
        },
      ),
      ...MusicNavigationHelper.createNavigationMenuOptions(context, songId),
      // Show 'Save to disk' for non-device files that are available offline
      if (!isDeviceFile &&
          song['on_device_status'] == 'true' &&
          song['on_device_filename'] != null &&
          (song['on_device_filename'] as String).isNotEmpty)
        PopupMenuOption(
          id: 'save_to_disk',
          label: 'Save to disk',
          onSelected: () => SaveToDiskHelper.saveToDisk(
            context: context,
            songId: songId,
            sourceFilePath: song['on_device_filename'] as String?,
            songTitle: songTitle,
            artistName: song['artists'] as String?,
          ),
        ),
      // Download / Redownload options (not for device files)
      if (!isDeviceFile)
        ...DownloadMenuHelper.createDownloadMenuOptions(
          songId: songId,
          context: context,
          onComplete: _loadSongs,
        ),
      if (isDeviceFile)
        PopupMenuOption(
          id: 'delete_from_device',
          label: 'Delete from device',
          onSelected: () => _deleteFromDevice(songId, song),
        )
      else
        PopupMenuOption(
          id: 'remove_from_library',
          label: 'Remove from library',
          onSelected: () => _removeFromLibrary(songId, songTitle),
        ),
    ];
  }

  Future<void> _deleteFromDevice(
    String songId,
    Map<String, dynamic> song,
  ) async {
    final songTitle = song['title'] as String?;
    final filePath =
        song['on_device_filename'] as String? ?? song['file_path'] as String?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from device?'),
        content: Text(
          'Are you sure you want to delete "${songTitle ?? 'this song'}" from your device? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('AlbumsList: Deleted device file: $filePath');
        }
      }

      await DatabaseHelper.instance.deleteSong(songId);
      _loadSongs();

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Deleted "${songTitle ?? 'song'}" from device',
          duration: const Duration(milliseconds: 1500),
        );
      }
    } catch (e) {
      debugPrint('AlbumsList: Error deleting song: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to delete song',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _removeFromLibrary(String songId, String? songTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
          'Are you sure you want to remove "${songTitle ?? 'this song'}" from your library? This will also delete any offline files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final song = await DatabaseHelper.instance.getSong(songId);
      if (song != null) {
        final filePath = song['on_device_filename'] as String?;
        if (filePath != null && filePath.isNotEmpty) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      await DatabaseHelper.instance.deleteSong(songId);
      _loadSongs();

      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Removed "${songTitle ?? 'song'}" from library',
          duration: const Duration(milliseconds: 1500),
        );
      }
    } catch (e) {
      debugPrint('AlbumsList: Error removing song: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to remove song',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  void _toggleAlbum(String album) {
    setState(() {
      if (_expandedAlbum == album) {
        _expandedAlbum = null;
      } else {
        _expandedAlbum = album;
      }
    });
  }

  String _getAlbumArtist(List<Map<String, dynamic>> songs) {
    if (songs.isEmpty) return 'Unknown Artist';
    // Get artists from first song
    final artists = songs.first['artists'] as String?;
    return (artists != null && artists.isNotEmpty) ? artists : 'Unknown Artist';
  }

  Widget _buildAlbumTile(String album) {
    final songs = _albumSongs[album] ?? [];
    final songCount = songs.length;
    final isExpanded = _expandedAlbum == album;
    // Use first song's ID for album art
    final firstSongId = songs.isNotEmpty ? songs.first['id'] as String : '';
    final albumArtist = _getAlbumArtist(songs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Album header tile
        InkWell(
          onTap: () => _toggleAlbum(album),
          child: Container(
            padding: const EdgeInsets.only(
              left: 8,
              right: 16,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                // Album thumbnail
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: firstSongId.isNotEmpty
                        ? AlbumArtWidget(
                            songId: firstSongId,
                            width: 56,
                            height: 56,
                            autoDownload: true,
                          )
                        : Stack(
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
                                  Icons.album,
                                  size: 28,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // Album name, artist, and song count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        album,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        albumArtist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$songCount song${songCount == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(180),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Expand/collapse indicator
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded songs list - only build when expanded
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(songs.length, (index) {
                final song = songs[index];
                final songId = song['id'] as String;

                return SongTile.fromData(
                  songId: songId,
                  songData: song,
                  onTap: () => _playAlbumSongs(album, index),
                  menuOptions: _getMenuOptions(songId, song),
                );
              }),
            ),
          ),
      ],
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

    if (_sortedAlbums.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No albums in your library',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Album count header
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            '${_sortedAlbums.length} album${_sortedAlbums.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Album tiles
        for (final album in _sortedAlbums) _buildAlbumTile(album),
      ],
    );
  }
}
