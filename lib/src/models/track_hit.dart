/// Minimal UI model built from your backend /v1/search items.
/// Keep it lean and store the raw map for future needs.
library;

class TrackHit {
  final String? id; // Mongo _id (if available)
  final String title;
  final String? album;
  final List<String> artists;
  final int? durationMs;

  /// A convenient artwork URL for list rows (client will choose size).
  final String? artworkUrl;

  /// The largest available artwork URL (useful for now playing)
  final String? largestArtworkUrl;

  /// External (Spotify) info to open in app/browser
  final String? spotifyUrl;

  /// Keep raw item for future features
  final Map<String, dynamic> raw;

  const TrackHit({
    required this.id,
    required this.title,
    required this.album,
    required this.artists,
    required this.durationMs,
    required this.artworkUrl,
    required this.largestArtworkUrl,
    required this.spotifyUrl,
    required this.raw,
  });

  factory TrackHit.fromSearchItem(Map<String, dynamic> item) {
    final List images = (item['artwork']?['images'] as List?) ?? const [];
    // pick an image near 64px (client-side pick kept simple here)
    String? artUrl;
    int bestDiff = 1 << 30;
    for (final im in images) {
      final url = im['url'];
      final w = (im['width'] as int?) ?? 9999;
      final d = (w - 64).abs();
      if (url != null && url.toString().isNotEmpty && d < bestDiff) {
        artUrl = url.toString();
        bestDiff = d;
      }
    }

    // If no small image found, try to get any image
    if (artUrl == null && images.isNotEmpty) {
      for (final im in images) {
        final url = im['url'];
        if (url != null && url.toString().isNotEmpty) {
          artUrl = url.toString();
          break;
        }
      }
    }

    return TrackHit(
      id: item['_id']?.toString(),
      title: (item['title'] ?? '(untitled)') as String,
      album: item['album'] as String?,
      artists: ((item['artists'] as List?) ?? []).cast<String>(),
      durationMs: item['durationMs'] as int?,
      artworkUrl: artUrl,
      largestArtworkUrl: _pickLargestImageUrl(images),
      spotifyUrl: item['ext']?['spotify']?['url'] as String?,
      raw: Map<String, dynamic>.from(item),
    );
  }

  static String? _pickLargestImageUrl(List images) {
    String? best;
    int bestW = 0;
    for (final im in images) {
      final url = im['url'];
      final w = (im['width'] as int?) ?? 0;
      if (url != null && url.toString().isNotEmpty && w > bestW) {
        bestW = w;
        best = url.toString();
      }
    }
    // If no image found with width, just return the first valid one
    if (best == null && images.isNotEmpty) {
      for (final im in images) {
        final url = im['url'];
        if (url != null && url.toString().isNotEmpty) {
          return url.toString();
        }
      }
    }
    return best;
  }
}
