import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../helpers/liked_songs_helper.dart';

/// Simple heart icon that shows filled heart when liked, outlined otherwise.
class LikedHeart extends StatelessWidget {
  final bool liked;
  final double size;

  const LikedHeart({super.key, required this.liked, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    final color = liked
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).iconTheme.color;
    return Icon(
      liked ? Icons.favorite : Icons.favorite_border,
      color: color,
      size: size,
    );
  }
}

/// DB-backed wrapper that queries `liked_status` for a song id and shows
/// the corresponding heart icon.
class LikedHeartFromId extends StatelessWidget {
  final String songId;
  final double size;

  const LikedHeartFromId({super.key, required this.songId, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    if (songId.isEmpty) return const LikedHeart(liked: false);
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseHelper.instance.getSong(songId),
      builder: (context, snapshot) {
        final row = snapshot.data;
        final liked =
            row != null &&
            (row['liked_status'] == 'true' ||
                row['liked_status'] == true ||
                row['liked_status'] == 1);
        return LikedHeart(liked: liked, size: size);
      },
    );
  }
}

/// Tappable heart button that toggles liked status and updates the liked songs playlist
class TappableLikedHeart extends StatefulWidget {
  final String songId;
  final double size;
  final VoidCallback? onToggle;
  // Optional asynchronous callback invoked before toggling liked status.
  // Use this to persist song data (e.g. from the SongTile) before the
  // heart's toggle updates the DB.
  final Future<void> Function()? onBeforeToggle;

  const TappableLikedHeart({
    super.key,
    required this.songId,
    this.size = 24.0,
    this.onToggle,
    this.onBeforeToggle,
  });

  @override
  State<TappableLikedHeart> createState() => _TappableLikedHeartState();
}

class _TappableLikedHeartState extends State<TappableLikedHeart> {
  bool _isLiked = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLikedStatus();
  }

  @override
  void didUpdateWidget(TappableLikedHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loadLikedStatus();
    }
  }

  Future<void> _loadLikedStatus() async {
    if (widget.songId.isEmpty) return;

    final liked = await LikedSongsHelper.isLiked(widget.songId);
    if (mounted) {
      setState(() {
        _isLiked = liked;
      });
    }
  }

  Future<void> _toggleLiked() async {
    if (widget.songId.isEmpty || _isLoading) return;

    debugPrint(
      'TappableLikedHeart._toggleLiked: starting toggle for songId = ${widget.songId}, current _isLiked = $_isLiked',
    );

    setState(() {
      _isLoading = true;
    });

    try {
      // Allow caller (e.g. SongTile.custom) to persist the song before
      // toggling liked status. This ensures the DB row exists and has the
      // correct data shape.
      if (widget.onBeforeToggle != null) {
        debugPrint('TappableLikedHeart._toggleLiked: calling onBeforeToggle');
        await widget.onBeforeToggle!();
        // Reload liked status after persistence to ensure UI matches DB state
        await _loadLikedStatus();
        debugPrint(
          'TappableLikedHeart._toggleLiked: after onBeforeToggle, reloaded _isLiked = $_isLiked',
        );
      }
      final newLikedStatus = await LikedSongsHelper.toggleLikedStatus(
        widget.songId,
      );
      debugPrint(
        'TappableLikedHeart._toggleLiked: toggle returned newLikedStatus = $newLikedStatus',
      );
      if (mounted) {
        setState(() {
          _isLiked = newLikedStatus;
          _isLoading = false;
        });
        widget.onToggle?.call();
      }
    } catch (e) {
      debugPrint('TappableLikedHeart: Error toggling liked status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songId.isEmpty) {
      return LikedHeart(liked: false, size: widget.size);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.size / 2),
        onTap: () {
          debugPrint(
            'TappableLikedHeart: InkWell onTap triggered for songId = ${widget.songId}',
          );
          _toggleLiked();
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isLoading
              ? SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : LikedHeart(
                  liked: _isLiked,
                  size: widget.size,
                  key: ValueKey(_isLiked),
                ),
        ),
      ),
    );
  }
}
