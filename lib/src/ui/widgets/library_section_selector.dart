import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/// Check if running on desktop platform
bool get _isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Library section types
enum LibrarySection { allSongs, playlists, artists, albums }

/// Extension to get display names
extension LibrarySectionExtension on LibrarySection {
  String get displayName {
    switch (this) {
      case LibrarySection.allSongs:
        return 'Songs';
      case LibrarySection.playlists:
        return 'Playlists';
      case LibrarySection.artists:
        return 'Artists';
      case LibrarySection.albums:
        return 'Albums';
    }
  }

  IconData get icon {
    switch (this) {
      case LibrarySection.allSongs:
        return Icons.music_note_rounded;
      case LibrarySection.playlists:
        return Icons.playlist_play_rounded;
      case LibrarySection.artists:
        return Icons.person_rounded;
      case LibrarySection.albums:
        return Icons.album_rounded;
    }
  }
}

/// A horizontal tab selector for library sections - minimal text-only design
class LibrarySectionSelector extends StatefulWidget {
  final LibrarySection initialSection;
  final ValueChanged<LibrarySection> onSectionChanged;

  /// Optional: external section to sync with (e.g., from PageView swipe)
  final LibrarySection? currentSection;

  const LibrarySectionSelector({
    super.key,
    this.initialSection = LibrarySection.playlists,
    required this.onSectionChanged,
    this.currentSection,
  });

  @override
  State<LibrarySectionSelector> createState() => _LibrarySectionSelectorState();
}

class _LibrarySectionSelectorState extends State<LibrarySectionSelector> {
  late LibrarySection _selectedSection;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.currentSection ?? widget.initialSection;
  }

  @override
  void didUpdateWidget(LibrarySectionSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync with external section changes (e.g., from PageView swipe)
    if (widget.currentSection != null &&
        widget.currentSection != _selectedSection) {
      setState(() {
        _selectedSection = widget.currentSection!;
      });
    }
  }

  void _onSectionTap(LibrarySection section) {
    if (section != _selectedSection) {
      setState(() {
        _selectedSection = section;
      });
      widget.onSectionChanged(section);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Configurable values
    const double fontSize = 20;
    const double horizontalPadding = 5;
    const double bottomGap = 12;

    return Padding(
      padding: const EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        bottom: bottomGap,
      ),
      child: Row(
        // On mobile use spaceBetween, on desktop use start with fixed spacing
        mainAxisAlignment: _isDesktopPlatform
            ? MainAxisAlignment.start
            : MainAxisAlignment.spaceBetween,
        children: LibrarySection.values.map((section) {
          final isSelected = section == _selectedSection;

          final textWidget = Text(
            section.displayName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.4),
            ),
          );

          return GestureDetector(
            onTap: () => _onSectionTap(section),
            behavior: HitTestBehavior.opaque,
            child: _isDesktopPlatform
                ? Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: textWidget,
                  )
                : textWidget,
          );
        }).toList(),
      ),
    );
  }
}
