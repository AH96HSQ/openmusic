import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../models/album.dart';
import '../../services/spotify_client.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/status_message_controller.dart';
import '../../data/database_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import '../widgets/song_tile.dart';
import 'add_to_playlist_bottom_sheet.dart';

class AlbumBottomSheet extends StatefulWidget {
  final String? albumId;
  final String? albumName;
  final String? songId; // New: fetch album from song ID

  const AlbumBottomSheet({super.key, this.albumId, this.albumName, this.songId})
    : assert(
        albumId != null || songId != null,
        'Either albumId or songId must be provided',
      );

  @override
  State<AlbumBottomSheet> createState() => _AlbumBottomSheetState();
}

class _AlbumBottomSheetState extends State<AlbumBottomSheet> {
  Album? _album;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    try {
      String? albumIdToFetch = widget.albumId;

      // If songId is provided, fetch track details first to get albumId
      if (widget.songId != null) {
        final track = await SpotifyClient.instance.getTrack(widget.songId!);
        if (track == null) {
          debugPrint('AlbumBottomSheet: Could not find track ${widget.songId}');
          if (mounted) setState(() => _loading = false);
          return;
        }
        albumIdToFetch = track.albumId;

        if (albumIdToFetch == null || albumIdToFetch.isEmpty) {
          debugPrint(
            'AlbumBottomSheet: No album ID found for song ${widget.songId}',
          );
          if (mounted) setState(() => _loading = false);
          return;
        }
      }

      final albumData = await SpotifyClient.instance.getAlbum(albumIdToFetch!);
      if (albumData != null && mounted) {
        setState(() {
          _album = Album.fromSpotifyJson(albumData);
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('AlbumBottomSheet: Error loading album: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getArtworkUrl(List<AlbumImage> images) {
    if (images.isEmpty) return '';
    // Return the largest image
    images.sort((a, b) => (b.width ?? 0).compareTo(a.width ?? 0));
    return images.first.url;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final navBg = theme.brightness == Brightness.dark
        ? Color.lerp(scaffoldBg, Colors.white, 0.06)!
        : Color.lerp(scaffoldBg, Colors.black, 0.02)!;

    return Container(
      height: maxHeight,
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(top: 25, bottom: 30, left: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.albumName ?? 'Loading...',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Album',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (_album != null)
            Padding(
              padding: const EdgeInsets.only(
                top: 25,
                bottom: 30,
                left: 20,
                right: 20,
              ),
              child: Row(
                children: [
                  // Album artwork
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: _getArtworkUrl(_album!.images).isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _getArtworkUrl(_album!.images),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.album,
                                  size: 40,
                                  color: theme.colorScheme.onSurfaceVariant,
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.album,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _album!.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _album!.artists.join(', '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_album!.tracks.length} tracks',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Content
          if (_loading)
            Expanded(
              child: Center(
                child: LoadingAnimationWidget.threeArchedCircle(
                  color: theme.colorScheme.primary,
                  size: 50,
                ),
              ),
            )
          else if (_album == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load album',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please try again',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_album!.tracks.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tracks in this album',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _album!.tracks.length,
                itemBuilder: (context, index) {
                  final track = _album!.tracks[index];
                  final songId = track.id;

                  return Container(
                    key: ValueKey(songId),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: SongTile.custom(
                      songId: songId,
                      title: track.name,
                      artists: track.artists.join(', '),
                      album: _album!.name,
                      albumArtUrl: _getArtworkUrl(_album!.images),
                      raw: {
                        'id': track.id,
                        'title': track.name,
                        'artists': track.artists,
                        'album': _album!.name,
                        'duration_ms': track.durationMs,
                        'track_number': track.trackNumber,
                        'external_urls': {'spotify': track.spotifyUrl},
                      },
                      onTap: () async {
                        debugPrint(
                          'albums and artists playback: Album track tapped - songId: $songId, trackName: ${track.name}, index: $index',
                        );

                        try {
                          // First check if track exists in local database
                          debugPrint(
                            'albums and artists playback: Checking local database for songId: $songId',
                          );

                          var localTrack = await DatabaseHelper.instance
                              .getSong(songId);

                          if (localTrack == null || localTrack['ext'] == null) {
                            debugPrint(
                              'albums and artists playback: Track not in local database or incomplete, checking if batch fetch needed',
                            );

                            // Check how many album tracks are missing from database
                            final allAlbumTrackIds = _album!.tracks
                                .map((t) => t.id)
                                .toList();

                            final missingTrackIds = <String>[];
                            for (String trackId in allAlbumTrackIds) {
                              final existingTrack = await DatabaseHelper
                                  .instance
                                  .getSong(trackId);
                              if (existingTrack == null ||
                                  existingTrack['ext'] == null) {
                                missingTrackIds.add(trackId);
                              }
                            }

                            if (missingTrackIds.isNotEmpty) {
                              debugPrint(
                                'albums and artists playback: Batch fetching ${missingTrackIds.length}/${allAlbumTrackIds.length} missing album tracks: $missingTrackIds',
                              );

                              // Fetch complete track details for missing tracks in parallel using SpotifyClient
                              final fetchFutures = missingTrackIds
                                  .map(
                                    (trackId) => SpotifyClient.instance
                                        .getTrack(trackId)
                                        .then(
                                          (track) =>
                                              track?.toSearchItem() ??
                                              <String, dynamic>{},
                                        )
                                        .catchError((e) {
                                          debugPrint(
                                            'albums and artists playback: Failed to fetch track $trackId: $e',
                                          );
                                          return <String, dynamic>{};
                                        }),
                                  )
                                  .toList();

                              final allTrackDataList = await Future.wait(
                                fetchFutures,
                              );

                              // Save missing tracks to database
                              int savedCount = 0;
                              for (
                                int i = 0;
                                i < allTrackDataList.length;
                                i++
                              ) {
                                final trackData = allTrackDataList[i];
                                if (trackData.isNotEmpty) {
                                  try {
                                    await DatabaseHelper.instance.insertSong(
                                      trackData,
                                    );
                                    savedCount++;
                                  } catch (e) {
                                    debugPrint(
                                      'albums and artists playback: Error saving track ${missingTrackIds[i]} to local database: $e',
                                    );
                                  }
                                }
                              }

                              debugPrint(
                                'albums and artists playback: Successfully batch saved $savedCount/${missingTrackIds.length} missing album tracks to local database',
                              );
                            } else {
                              debugPrint(
                                'albums and artists playback: All album tracks already in local database',
                              );
                            }
                          } else {
                            debugPrint(
                              'albums and artists playback: Track found in local database: $songId',
                            );
                          }

                          // Create queue from all album tracks
                          final albumTrackIds = _album!.tracks
                              .map((t) => t.id)
                              .toList();
                          debugPrint(
                            'albums and artists playback: Created album queue with ${albumTrackIds.length} tracks: $albumTrackIds',
                          );

                          // Set the queue starting from the selected track
                          debugPrint(
                            'albums and artists playback: Setting queue with startIndex: $index',
                          );
                          await QueueService.instance.setQueue(
                            albumTrackIds,
                            startIndex: index,
                            context: PlaybackContext.album,
                          );
                          debugPrint(
                            'albums and artists playback: Queue set successfully',
                          );

                          // Start playback - track is now in database, no raw data needed
                          debugPrint(
                            'albums and artists playback: Starting playback for songId: $songId (no raw data)',
                          );
                          final playbackResult = await SimplePlaybackController
                              .instance
                              .play(songId, null);

                          if (playbackResult == null) {
                            debugPrint(
                              'albums and artists playback: Playback started successfully for $songId',
                            );
                          } else {
                            debugPrint(
                              'albums and artists playback: Playback error for $songId: $playbackResult',
                            );
                          }

                          // Play count will be automatically tracked by SimplePlaybackController

                          debugPrint(
                            'albums and artists playback: Successfully completed album track playback for $songId at index $index',
                          );
                        } catch (e, stackTrace) {
                          debugPrint(
                            'albums and artists playback: ERROR playing album track $songId: $e',
                          );
                          debugPrint(
                            'albums and artists playback: Stack trace: $stackTrace',
                          );
                        }
                      },
                      menuOptions: [
                        PopupMenuOption(
                          id: 'play_next',
                          label: 'Play Next',
                          onSelected: () async {
                            await QueueService.instance.playNext(songId);
                            StatusMessageController.instance.showMessage(
                              'Will play "${track.name}" next',
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
                              'Added "${track.name}" to queue',
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
                                songTitle: track.name,
                              );
                            }
                          },
                        ),
                        PopupMenuOption(
                          id: 'save_to_disk',
                          label: 'Save to disk',
                          onSelected: () async {
                            final song = await DatabaseHelper.instance.getSong(
                              songId,
                            );
                            if (song != null && context.mounted) {
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
                                  context: context,
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
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper function to show the album bottom sheet
Future<void> showAlbumBottomSheet(
  BuildContext context, {
  String? albumId,
  String? albumName,
  String? songId,
}) async {
  assert(
    albumId != null || songId != null,
    'Either albumId or songId must be provided',
  );

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => AlbumBottomSheet(
      albumId: albumId,
      albumName: albumName,
      songId: songId,
    ),
  );
}
