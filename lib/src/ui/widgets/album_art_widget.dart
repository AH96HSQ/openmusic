import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/album_art_helper.dart';
import 'package:animate_gradient/animate_gradient.dart';

/// A widget that displays album artwork with automatic offline caching
/// Falls back to network image if local copy isn't available, then to default icon
class AlbumArtWidget extends StatefulWidget {
  final String songId;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final bool autoDownload;

  const AlbumArtWidget({
    super.key,
    required this.songId,
    this.width = 56,
    this.height = 56,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.autoDownload = true,
  });

  @override
  State<AlbumArtWidget> createState() => _AlbumArtWidgetState();
}

class _AlbumArtWidgetState extends State<AlbumArtWidget> {
  String? _localPath;
  String? _networkUrl;
  bool _isLoading = true;
  bool _hasError = false;
  bool _downloadAttempted = false; // Prevents infinite download loops

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(AlbumArtWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _downloadAttempted = false; // Reset for new song
      _loadArtwork();
    }
  }

  Future<void> _loadArtwork() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _localPath = null;
      _networkUrl = null;
    });

    try {
      final helper = AlbumArtHelper.instance;

      // First try to get local artwork (checks in-memory cache first, then DB)
      final localPath = await helper.getLocalArtworkPath(widget.songId);

      if (localPath != null && mounted) {
        setState(() {
          _localPath = localPath;
          _isLoading = false;
        });
        return;
      }

      // If no local artwork, get network URL
      final networkUrl = await helper.getArtworkUrl(widget.songId);

      if (mounted) {
        setState(() {
          _networkUrl = networkUrl;
          _isLoading = false;
        });

        // Only try to download once per widget instance to prevent infinite loops
        if (widget.autoDownload &&
            networkUrl != null &&
            networkUrl.isNotEmpty &&
            !_downloadAttempted) {
          _downloadAttempted =
              true; // Mark as attempted BEFORE starting download
          // Don't wait for download - let it happen in background
          helper
              .downloadArtworkForSong(widget.songId)
              .then((downloadedPath) {
                // Only update state if download succeeded and returned a path
                if (downloadedPath != null && mounted) {
                  setState(() {
                    _localPath = downloadedPath;
                    _networkUrl = null;
                  });
                }
              })
              .catchError((error) {
                debugPrint(
                  'AlbumArtWidget: Background download failed for ${widget.songId}: $error',
                );
              });
        }
      }
    } catch (e) {
      debugPrint(
        'AlbumArtWidget: Error loading artwork for ${widget.songId}: $e',
      );
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildDefaultIcon() {
    // Calculate safe icon size with bounds checking
    final safeWidth = widget.width.isFinite ? widget.width : 56.0;
    final safeHeight = widget.height.isFinite ? widget.height : 56.0;
    final minDimension = safeWidth < safeHeight ? safeWidth : safeHeight;
    final iconSize = (minDimension * 0.6).clamp(24.0, 120.0);

    // Use animated gradient as the default background with the music icon overlaid
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
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
              child: Icon(
                Icons.music_note,
                color: const Color.fromARGB(255, 255, 255, 255),
                size: iconSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    // Calculate safe loading indicator size with bounds checking
    final safeWidth = widget.width.isFinite ? widget.width : 56.0;
    final safeHeight = widget.height.isFinite ? widget.height : 56.0;
    final minDimension = safeWidth < safeHeight ? safeWidth : safeHeight;
    final loadingSize = (minDimension * 0.3).clamp(16.0, 32.0);

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
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
              child: SizedBox(
                width: loadingSize,
                height: loadingSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_hasError) {
      return _buildDefaultIcon();
    }

    Widget child;

    if (_localPath != null) {
      // Use local file
      child = Image.file(
        File(_localPath!),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('AlbumArtWidget: Local file error: $error');
          return _buildDefaultIcon();
        },
      );
    } else if (_networkUrl != null && _networkUrl!.isNotEmpty) {
      // Use network image
      child = Image.network(
        _networkUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('AlbumArtWidget: Network image error: $error');
          return _buildDefaultIcon();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return _buildLoadingWidget();
        },
      );
    } else {
      // No artwork available - show animated gradient fallback
      child = _buildDefaultIcon();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
      child: child,
    );
  }
}
