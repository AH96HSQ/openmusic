import 'package:flutter/material.dart';
import 'album_art_widget.dart';

/// Widget that displays playlist artwork as a collage of top played songs
/// Shows 4 album arts in a 2x2 grid if there are 4+ songs with play history,
/// otherwise shows a single album art from the top played song
class PlaylistArtWidget extends StatelessWidget {
  final List<String> topSongIds;
  final double width;
  final double height;

  const PlaylistArtWidget({
    super.key,
    required this.topSongIds,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (topSongIds.isEmpty) {
      // No songs - return empty container (caller should show default icon)
      return SizedBox(width: width, height: height);
    }

    if (topSongIds.length < 4) {
      // Less than 4 songs - show single album art from top played song
      return AlbumArtWidget(
        songId: topSongIds.first,
        width: width,
        height: height,
        autoDownload: false,
      );
    }

    // 4+ songs - show 2x2 collage
    final halfWidth = width / 2;
    final halfHeight = height / 2;

    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: halfWidth,
                height: halfHeight,
                child: AlbumArtWidget(
                  songId: topSongIds[0],
                  width: halfWidth,
                  height: halfHeight,
                  autoDownload: false,
                ),
              ),
              SizedBox(
                width: halfWidth,
                height: halfHeight,
                child: AlbumArtWidget(
                  songId: topSongIds[1],
                  width: halfWidth,
                  height: halfHeight,
                  autoDownload: false,
                ),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: halfWidth,
                height: halfHeight,
                child: AlbumArtWidget(
                  songId: topSongIds[2],
                  width: halfWidth,
                  height: halfHeight,
                  autoDownload: false,
                ),
              ),
              SizedBox(
                width: halfWidth,
                height: halfHeight,
                child: AlbumArtWidget(
                  songId: topSongIds[3],
                  width: halfWidth,
                  height: halfHeight,
                  autoDownload: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
