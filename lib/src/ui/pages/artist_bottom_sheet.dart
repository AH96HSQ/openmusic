import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../models/artist.dart';
import '../../services/spotify_client.dart';
import '../../services/simple_playback_controller.dart';
import '../../services/queue_service.dart';
import '../../services/status_message_controller.dart';
import '../../data/database_helper.dart';
import '../../helpers/save_to_disk_helper.dart';
import 'album_bottom_sheet.dart';

class ArtistBottomSheet extends StatefulWidget {
  final String? artistId;
  final String? artistName;
  final String? songId; // New: fetch artist from song ID

  const ArtistBottomSheet({
    super.key,
    this.artistId,
    this.artistName,
    this.songId,
  }) : assert(
         artistId != null || songId != null,
         'Either artistId or songId must be provided',
       );

  @override
  State<ArtistBottomSheet> createState() => _ArtistBottomSheetState();
}

class _ArtistBottomSheetState extends State<ArtistBottomSheet> {
  Artist? _artist;
  ArtistTopTracks? _topTracks;
  ArtistAlbums? _albums;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadArtistData();
  }

  Future<void> _loadArtistData() async {
    try {
      String? artistIdToFetch = widget.artistId;

      // If songId is provided, fetch track details first to get artistId
      if (widget.songId != null) {
        final track = await SpotifyClient.instance.getTrack(widget.songId!);
        if (track == null || track.artistIds.isEmpty) {
          debugPrint(
            'ArtistBottomSheet: No artist IDs found for song ${widget.songId}',
          );
          if (mounted) setState(() => _loading = false);
          return;
        }
        // Use the first (primary) artist
        artistIdToFetch = track.artistIds.first;
      }

      // Load artist details, top tracks, and albums in parallel
      final futures = await Future.wait([
        SpotifyClient.instance.getArtist(artistIdToFetch!),
        SpotifyClient.instance.getArtistTopTracks(artistIdToFetch),
        SpotifyClient.instance.getArtistAlbums(artistIdToFetch, limit: 10),
      ]);

      final artistData = futures[0] as Map<String, dynamic>?;
      final topTracks = futures[1] as List<SpotifyTrack>;
      final albumsData = futures[2] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _artist = artistData != null
              ? Artist.fromSpotifyJson(artistData)
              : null;
          _topTracks = ArtistTopTracks(
            artistId: artistIdToFetch!,
            tracks: topTracks
                .map(
                  (t) => ArtistTrack(
                    id: t.id,
                    name: t.title,
                    album: t.album,
                    artists: t.artists,
                    durationMs: t.durationMs,
                    popularity: t.popularity,
                    spotifyUrl: t.url,
                    images: t.images
                        .map(
                          (img) => ArtistImage(
                            url: img['url'] as String? ?? '',
                            width: img['width'] as int?,
                            height: img['height'] as int?,
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          );
          _albums = albumsData != null
              ? ArtistAlbums.fromSpotifyJson(artistIdToFetch, albumsData)
              : null;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ArtistBottomSheet: Error loading artist data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getArtworkUrl(List<ArtistImage> images) {
    if (images.isEmpty) return '';
    // Return the largest image
    images.sort((a, b) => (b.width ?? 0).compareTo(a.width ?? 0));
    return images.first.url;
  }

  String _formatFollowers(int? followers) {
    if (followers == null) return '';
    if (followers >= 1000000) {
      return '${(followers / 1000000).toStringAsFixed(1)}M followers';
    } else if (followers >= 1000) {
      return '${(followers / 1000).toStringAsFixed(1)}K followers';
    }
    return '$followers followers';
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
                          widget.artistName ?? 'Loading...',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Artist',
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
          else if (_artist != null)
            Padding(
              padding: const EdgeInsets.only(
                top: 25,
                bottom: 30,
                left: 20,
                right: 20,
              ),
              child: Row(
                children: [
                  // Artist image
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: _getArtworkUrl(_artist!.images).isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: Image.network(
                              _getArtworkUrl(_artist!.images),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.person,
                                  size: 40,
                                  color: theme.colorScheme.onSurfaceVariant,
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.person,
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
                          _artist!.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_artist!.followers != null)
                          Text(
                            _formatFollowers(_artist!.followers),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (_artist!.genres.isNotEmpty)
                          Text(
                            _artist!.genres.take(2).join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
          else if (_artist == null || _topTracks == null)
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
                      'Failed to load artist',
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
          else if (_topTracks!.tracks.isEmpty)
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
                      'No top tracks available',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Tracks Section (Horizontal)
                    if (_topTracks!.tracks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Text(
                          'Top Tracks',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // Horizontal tracks wheel
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _topTracks!.tracks.length,
                          itemBuilder: (context, index) {
                            final track = _topTracks!.tracks[index];
                            final songId = track.id;

                            return Container(
                              key: ValueKey(songId),
                              width: 140,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              child: GestureDetector(
                                onTap: () async {
                                  debugPrint(
                                    'albums and artists playback: Artist track tapped - songId: $songId, trackName: ${track.name}, index: $index',
                                  );

                                  try {
                                    // First check if track exists in local database
                                    debugPrint(
                                      'albums and artists playback: Checking local database for songId: $songId',
                                    );

                                    var localTrack = await DatabaseHelper
                                        .instance
                                        .getSong(songId);

                                    if (localTrack == null ||
                                        localTrack['ext'] == null) {
                                      debugPrint(
                                        'albums and artists playback: Track not in local database or incomplete, checking if batch fetch needed',
                                      );

                                      // Check how many top tracks are missing from database
                                      final allTopTrackIds = _topTracks!.tracks
                                          .map((t) => t.id)
                                          .toList();

                                      final missingTrackIds = <String>[];
                                      for (String trackId in allTopTrackIds) {
                                        final existingTrack =
                                            await DatabaseHelper.instance
                                                .getSong(trackId);
                                        if (existingTrack == null ||
                                            existingTrack['ext'] == null) {
                                          missingTrackIds.add(trackId);
                                        }
                                      }

                                      if (missingTrackIds.isNotEmpty) {
                                        debugPrint(
                                          'albums and artists playback: Batch fetching ${missingTrackIds.length}/${allTopTrackIds.length} missing top tracks: $missingTrackIds',
                                        );

                                        // Fetch complete track details for missing tracks in parallel using SpotifyClient
                                        final fetchFutures = missingTrackIds
                                            .map(
                                              (trackId) => SpotifyClient
                                                  .instance
                                                  .getTrack(trackId)
                                                  .then(
                                                    (track) =>
                                                        track?.toSearchItem() ??
                                                        <String, dynamic>{},
                                                  )
                                                  .catchError((e) {
                                                    debugPrint(
                                                      'albums and artists playback: Failed to fetch top track $trackId: $e',
                                                    );
                                                    return <String, dynamic>{};
                                                  }),
                                            )
                                            .toList();

                                        final allTrackDataList =
                                            await Future.wait(fetchFutures);

                                        // Save missing top tracks to database
                                        int savedCount = 0;
                                        for (
                                          int i = 0;
                                          i < allTrackDataList.length;
                                          i++
                                        ) {
                                          final trackData = allTrackDataList[i];
                                          if (trackData.isNotEmpty) {
                                            try {
                                              await DatabaseHelper.instance
                                                  .insertSong(trackData);
                                              savedCount++;
                                            } catch (e) {
                                              debugPrint(
                                                'albums and artists playback: Error saving top track ${missingTrackIds[i]} to local database: $e',
                                              );
                                            }
                                          }
                                        }

                                        debugPrint(
                                          'albums and artists playback: Successfully batch saved $savedCount/${missingTrackIds.length} missing top tracks to local database',
                                        );
                                      } else {
                                        debugPrint(
                                          'albums and artists playback: All top tracks already in local database',
                                        );
                                      }
                                    } else {
                                      debugPrint(
                                        'albums and artists playback: Track found in local database: $songId',
                                      );
                                    }

                                    // Create queue from all top tracks
                                    final topTrackIds = _topTracks!.tracks
                                        .map((t) => t.id)
                                        .toList();
                                    debugPrint(
                                      'albums and artists playback: Created artist queue with ${topTrackIds.length} tracks: $topTrackIds',
                                    );

                                    // Set the queue starting from the selected track
                                    debugPrint(
                                      'albums and artists playback: Setting artist queue with startIndex: $index',
                                    );
                                    await QueueService.instance.setQueue(
                                      topTrackIds,
                                      startIndex: index,
                                      context: PlaybackContext.artist,
                                    );
                                    debugPrint(
                                      'albums and artists playback: Artist queue set successfully',
                                    );

                                    // Start playback - track is now in database, no raw data needed
                                    debugPrint(
                                      'albums and artists playback: Starting playback for artist track songId: $songId (no raw data)',
                                    );
                                    final playbackResult =
                                        await SimplePlaybackController.instance
                                            .play(songId, null);

                                    if (playbackResult == null) {
                                      debugPrint(
                                        'albums and artists playback: Artist track playback started successfully for $songId',
                                      );
                                    } else {
                                      debugPrint(
                                        'albums and artists playback: Artist track playback error for $songId: $playbackResult',
                                      );
                                    }

                                    // Play count will be automatically tracked by SimplePlaybackController

                                    debugPrint(
                                      'albums and artists playback: Successfully completed artist track playback for $songId at index $index',
                                    );
                                  } catch (e, stackTrace) {
                                    debugPrint(
                                      'albums and artists playback: ERROR playing artist track $songId: $e',
                                    );
                                    debugPrint(
                                      'albums and artists playback: Stack trace: $stackTrace',
                                    );
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Track artwork with 3-dot menu
                                    Stack(
                                      children: [
                                        Container(
                                          width: 140,
                                          height: 140,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                          child:
                                              _getArtworkUrl(
                                                track.images,
                                              ).isNotEmpty
                                              ? ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.network(
                                                    _getArtworkUrl(
                                                      track.images,
                                                    ),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return Icon(
                                                            Icons.music_note,
                                                            size: 40,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          );
                                                        },
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.music_note,
                                                  size: 40,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                        ),
                                        // 3-dot menu in top right
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: PopupMenuButton<String>(
                                            color: theme.colorScheme.surface,
                                            icon: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.7,
                                                ),
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
                                                await QueueService.instance
                                                    .playNext(songId);
                                                StatusMessageController.instance
                                                    .showMessage(
                                                      'Will play "${track.name}" next',
                                                      duration: const Duration(
                                                        milliseconds: 2200,
                                                      ),
                                                    );
                                              } else if (value ==
                                                  'add_to_queue') {
                                                await QueueService.instance
                                                    .addToQueue(songId);
                                                StatusMessageController.instance
                                                    .showMessage(
                                                      'Added "${track.name}" to queue',
                                                      duration: const Duration(
                                                        milliseconds: 2200,
                                                      ),
                                                    );
                                              } else if (value ==
                                                  'save_to_disk') {
                                                // Fetch song data to check if it's available
                                                final song =
                                                    await DatabaseHelper
                                                        .instance
                                                        .getSong(songId);
                                                if (song == null) {
                                                  StatusMessageController
                                                      .instance
                                                      .showMessage(
                                                        'Song not available offline',
                                                        duration:
                                                            const Duration(
                                                              milliseconds:
                                                                  2000,
                                                            ),
                                                      );
                                                  return;
                                                }

                                                final isDeviceFile =
                                                    song['source'] ==
                                                        'device' ||
                                                    song['is_device_file'] ==
                                                        'true';
                                                final isOfflineAvailable =
                                                    !isDeviceFile &&
                                                    song['on_device_status'] ==
                                                        'true' &&
                                                    song['on_device_filename'] !=
                                                        null &&
                                                    (song['on_device_filename']
                                                            as String)
                                                        .isNotEmpty;

                                                if (!isOfflineAvailable) {
                                                  StatusMessageController
                                                      .instance
                                                      .showMessage(
                                                        'Song not available offline',
                                                        duration:
                                                            const Duration(
                                                              milliseconds:
                                                                  2000,
                                                            ),
                                                      );
                                                  return;
                                                }

                                                if (context.mounted) {
                                                  SaveToDiskHelper.saveToDisk(
                                                    context: context,
                                                    songId: songId,
                                                    sourceFilePath:
                                                        song['on_device_filename']
                                                            as String?,
                                                    songTitle:
                                                        song['title']
                                                            as String?,
                                                    artistName:
                                                        song['artists']
                                                            as String?,
                                                  );
                                                }
                                              }
                                            },
                                            itemBuilder: (ctx) => [
                                              const PopupMenuItem<String>(
                                                value: 'play_next',
                                                child: Text('Play Next'),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: 'add_to_queue',
                                                child: Text('Queue up'),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: 'save_to_disk',
                                                child: Text('Save to disk'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Track name
                                    Text(
                                      track.name,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    // Albums Section (Discography)
                    if (_albums != null && _albums!.albums.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Text(
                          'Discography',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // Vertical albums list
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _albums!.albums.length,
                        itemBuilder: (context, index) {
                          final album = _albums!.albums[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              onTap: () async {
                                // Navigate to album bottom sheet
                                if (context.mounted) {
                                  await showAlbumBottomSheet(
                                    context,
                                    albumId: album.id,
                                    albumName: album.name,
                                  );
                                }
                              },
                              leading: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                                child: album.images.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          album.images.first.url,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Icon(
                                                  Icons.album,
                                                  size: 24,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                );
                                              },
                                        ),
                                      )
                                    : Icon(
                                        Icons.album,
                                        size: 24,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                              ),
                              title: Text(
                                album.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${album.albumType.toUpperCase()}${album.releaseDate != null ? ' • ${album.releaseDate!.substring(0, 4)}' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper function to show the artist bottom sheet
Future<void> showArtistBottomSheet(
  BuildContext context, {
  String? artistId,
  String? artistName,
  String? songId,
}) async {
  assert(
    artistId != null || songId != null,
    'Either artistId or songId must be provided',
  );

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => ArtistBottomSheet(
      artistId: artistId,
      artistName: artistName,
      songId: songId,
    ),
  );
}
