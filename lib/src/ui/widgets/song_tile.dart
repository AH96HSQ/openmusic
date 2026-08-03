import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:just_audio/just_audio.dart';
import 'package:animate_gradient/animate_gradient.dart';
import '../../data/database_helper.dart';
import '../widgets/liked_heart.dart';
import '../widgets/album_art_widget.dart';
import '../../services/simple_playback_controller.dart';

/// Option for popup menu in the song tile.
class PopupMenuOption {
  final String id;
  final String label;
  final VoidCallback? onSelected;

  /// Optional: if provided, will be called with song data to get dynamic label
  final String Function(Map<String, dynamic>? songData)? labelBuilder;

  /// Optional: custom widget to display instead of Text(label)
  final Widget? child;

  PopupMenuOption({
    required this.id,
    required this.label,
    this.onSelected,
    this.labelBuilder,
    this.child,
  });
}

/// A reusable song tile used for search results, playlist entries, album/artist lists, etc.
/// Two modes:
/// - custom mode: provide title, artists, albumArtUrl and songId
/// - database mode: provide only songId and tile will load data from DB
class SongTile extends StatelessWidget {
  final bool _isDbMode;

  // common
  final String songId;
  final VoidCallback? onTap;
  final List<PopupMenuOption>? menuOptions;

  // custom-only
  final String? title;
  final String? artists;
  final String? album;
  final String? albumArtUrl;
  final Map<String, dynamic>? raw;

  const SongTile._({
    super.key,
    required bool isDbMode,
    required this.songId,
    this.onTap,
    this.menuOptions,
    this.title,
    this.artists,
    this.album,
    this.albumArtUrl,
    this.raw,
  }) : _isDbMode = isDbMode;

  /// Create a tile in custom mode (e.g. search results). Must provide display fields.
  factory SongTile.custom({
    Key? key,
    required String songId,
    required String title,
    required String artists,
    String? album,
    String? albumArtUrl,
    Map<String, dynamic>? raw,
    VoidCallback? onTap,
    List<PopupMenuOption>? menuOptions,
  }) {
    return SongTile._(
      key: key,
      isDbMode: false,
      songId: songId,
      title: title,
      artists: artists,
      album: album,
      albumArtUrl: albumArtUrl,
      raw: raw,
      onTap: onTap,
      menuOptions: menuOptions,
    );
  }

  /// Create a tile in database mode — provide only the songId and the tile will
  /// fetch metadata from the database.
  factory SongTile.database({
    Key? key,
    required String songId,
    VoidCallback? onTap,
    List<PopupMenuOption>? menuOptions,
  }) {
    return SongTile._(
      key: key,
      isDbMode: true,
      songId: songId,
      onTap: onTap,
      menuOptions: menuOptions,
    );
  }

  /// Create a tile with pre-loaded song data (avoids database query).
  /// Use this when you already have the song data from a batch query.
  factory SongTile.fromData({
    Key? key,
    required String songId,
    required Map<String, dynamic> songData,
    VoidCallback? onTap,
    List<PopupMenuOption>? menuOptions,
  }) {
    final title = (songData['title'] as String?) ?? '';
    final artists = (songData['artists'] as String?) ?? '';
    final album = (songData['album'] as String?) ?? '';
    String? artwork = songData['artwork_largest'] as String?;
    try {
      if ((artwork ?? '').isEmpty) {
        final imagesJson = songData['artwork_images'] as String?;
        if (imagesJson != null && imagesJson.isNotEmpty) {
          final imgs = jsonDecode(imagesJson) as List<dynamic>;
          if (imgs.isNotEmpty) artwork = imgs.first['url'] as String?;
        }
      }
    } catch (_) {
      artwork = null;
    }

    return SongTile._(
      key: key,
      isDbMode: false, // Use custom mode since we have the data
      songId: songId,
      title: title,
      artists: artists,
      album: album,
      albumArtUrl: artwork,
      raw: songData,
      onTap: onTap,
      menuOptions: menuOptions,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDbMode) {
      return FutureBuilder<Map<String, dynamic>?>(
        future: DatabaseHelper.instance.getSong(songId),
        builder: (context, snapshot) {
          final row = snapshot.data;
          if (row == null) {
            // show an empty placeholder
            return _buildTile(context, '', '', '', '', null);
          }
          final title = (row['title'] as String?) ?? '';
          final artists = (row['artists'] as String?) ?? '';
          final album = (row['album'] as String?) ?? '';
          String? artwork = row['artwork_largest'] as String?;
          try {
            if ((artwork ?? '').isEmpty) {
              final imagesJson = row['artwork_images'] as String?;
              if (imagesJson != null && imagesJson.isNotEmpty) {
                final imgs = jsonDecode(imagesJson) as List<dynamic>;
                if (imgs.isNotEmpty) artwork = imgs.first['url'] as String?;
              }
            }
          } catch (_) {
            artwork = null;
          }
          return _buildTile(context, title, artists, album, artwork ?? '', row);
        },
      );
    }

    // custom mode - use raw data if available
    return _buildTile(
      context,
      title ?? '',
      artists ?? '',
      album ?? '',
      albumArtUrl ?? '',
      raw,
    );
  }

  Widget _buildTile(
    BuildContext context,
    String title,
    String artists,
    String album,
    String artworkUrl,
    Map<String, dynamic>? songData,
  ) {
    // Save a minimal song record when the tile is interacted with (tap)
    // For custom mode tiles (search results) we persist a minimal record so
    // the DB has the item for later DB-backed features. DB mode tiles are
    // already backed by the DB so we skip re-inserting.
    void handleTap() async {
      if (!_isDbMode) {
        try {
          final finalId =
              raw?['id']?.toString() ?? raw?['_id']?.toString() ?? songId;

          // Check if song already exists - if so, skip persistence to avoid
          // overwriting on_device_status and on_device_filename
          final existing = await DatabaseHelper.instance.getSong(finalId);
          if (existing == null) {
            if (raw != null && raw!.isNotEmpty) {
              // Use the backend-provided raw map as-is (ensure id key exists)
              final toSave = Map<String, dynamic>.from(raw!);
              toSave['id'] = finalId;
              await DatabaseHelper.instance.insertSong(toSave);
            } else {
              // fallback to minimal fields if raw not supplied
              await DatabaseHelper.instance.insertSong({
                'id': songId,
                'title': title,
                'artists': artists,
                'album': album,
                'artwork_largest': artworkUrl,
              });
            }
          }
        } catch (_) {
          // ignore DB errors for now; keep UX snappy
        }

        // Play count will be automatically tracked by SimplePlaybackController
      } else {
        // Play count will be automatically tracked by SimplePlaybackController
      }
      if (onTap != null) onTap!();
    }

    // Persist song if we're in custom mode and have raw data. This is used
    // by child controls (heart, menu) which may be pressed instead of the
    // primary tile area. Returns immediately if DB write is not needed.
    Future<void> persistSongIfNeeded() async {
      if (!_isDbMode) {
        try {
          if (raw != null && raw!.isNotEmpty) {
            final toSave = Map<String, dynamic>.from(raw!);
            final finalId = toSave['id'] ?? toSave['_id']?.toString() ?? songId;
            toSave['id'] = finalId;

            // Check if song already exists - if so, skip persistence
            final existing = await DatabaseHelper.instance.getSong(finalId);
            if (existing != null) {
              debugPrint(
                'SongTile.persistSongIfNeeded: song $finalId already exists, skipping persistence',
              );
              return;
            }

            debugPrint(
              'SongTile.persistSongIfNeeded: persisting with ID: $finalId, original songId: $songId',
            );
            debugPrint(
              'SongTile.persistSongIfNeeded: raw[id]: ${toSave['id']}, raw[_id]: ${raw!['_id']}',
            );
            await DatabaseHelper.instance.insertSong(toSave);
          } else {
            await DatabaseHelper.instance.insertSong({
              'id': songId,
              'title': title,
              'artists': artists,
              'album': album,
              'artwork_largest': artworkUrl,
            });
          }
        } catch (_) {
          // ignore
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 5.0, top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          // Main tappable area (album art + text content)
          Expanded(
            child: InkWell(
              onTap: handleTap,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              child: Row(
                children: [
                  // album art: use offline system for DB mode, direct network for search
                  _isDbMode
                      ? AlbumArtWidget(songId: songId, width: 56, height: 56)
                      : _buildSearchArtwork(context, artworkUrl),
                  const SizedBox(width: 15),

                  // title + artists column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          artists,
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

          // Right side icons with consistent spacing - these are their own tap targets
          _PlaybackIndicator(songId: songId),
          const SizedBox(width: 15),
          TappableLikedHeart(
            songId: songId,
            size: 24,
            onBeforeToggle: persistSongIfNeeded,
          ),
          if (menuOptions != null && menuOptions!.isNotEmpty) ...[
            const SizedBox(width: 0),
            PopupMenuButton<String>(
              color: Theme.of(context).colorScheme.surface,
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).iconTheme.color,
              ),
              onSelected: (value) async {
                // If the keyboard is open, dismiss it so the menu action
                // doesn't race with input changes.
                FocusScope.of(context).unfocus();

                // Ensure song is persisted before running menu action.
                await persistSongIfNeeded();

                final opt = menuOptions!.firstWhere(
                  (o) => o.id == value,
                  orElse: () => menuOptions!.first,
                );
                if (opt.onSelected != null) opt.onSelected!();
              },
              itemBuilder: (ctx) => menuOptions!.map((o) {
                // Use labelBuilder if available, otherwise use static label
                final displayLabel = o.labelBuilder != null
                    ? o.labelBuilder!(songData)
                    : o.label;
                return PopupMenuItem<String>(
                  value: o.id,
                  child: o.child ?? Text(displayLabel),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Build artwork widget for search results (custom mode)
  Widget _buildSearchArtwork(BuildContext context, String artworkUrl) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    Widget buildGradientFallback() {
      return SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
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
                child: Icon(Icons.music_note, color: Colors.white, size: 24),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: artworkUrl.isNotEmpty
          ? Image.network(
              artworkUrl,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return buildGradientFallback();
              },
            )
          : buildGradientFallback(),
    );
  }
}

/// Playback indicator that shows loading animation or music visualizer
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
