import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../services/simple_playback_controller.dart';

/// Small modular widget showing two tight checkmarks: client (left) and server (right).
class FileAvailabilityChecks extends StatelessWidget {
  final bool serverHas;
  final bool clientHas;
  final double size;
  final double spacing;

  const FileAvailabilityChecks({
    super.key,
    required this.serverHas,
    required this.clientHas,
    this.size = 24.0,
    this.spacing = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.primary;
    final offColor = Colors.grey;
    final iconSize = size * 0.9;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // left: client
        Icon(
          Icons.check,
          size: iconSize,
          color: clientHas ? onColor : offColor,
        ),
        SizedBox(width: spacing),
        // right: server
        Icon(
          Icons.check,
          size: iconSize,
          color: serverHas ? onColor : offColor,
        ),
      ],
    );
  }
}

/// Widget that accepts a song id, queries the database, and shows the
/// double checkmark UI: left = local (on_device_status), right = server (file_exists/file_id).
/// Listens to SimplePlaybackController for live updates.
class FileAvailabilityChecksFromId extends StatefulWidget {
  final String songId;
  final double size;
  final double spacing;

  const FileAvailabilityChecksFromId({
    super.key,
    required this.songId,
    this.size = 24.0,
    this.spacing = 4.0,
  });

  @override
  State<FileAvailabilityChecksFromId> createState() =>
      _FileAvailabilityChecksFromIdState();
}

class _FileAvailabilityChecksFromIdState
    extends State<FileAvailabilityChecksFromId> {
  Map<String, dynamic>? _songData;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadSongData();
    // Listen to playback controller changes which might indicate download completion
    SimplePlaybackController.instance.addListener(_onPlaybackControllerChange);
  }

  @override
  void dispose() {
    _hideTooltip(); // Clean up any active tooltip
    SimplePlaybackController.instance.removeListener(
      _onPlaybackControllerChange,
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(FileAvailabilityChecksFromId oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loadSongData();
    }
  }

  void _onPlaybackControllerChange() {
    // Reload data when playback controller changes (could indicate download completion)
    _loadSongData();
  }

  Future<void> _loadSongData() async {
    if (widget.songId.isEmpty) return;

    try {
      final data = await DatabaseHelper.instance.getSong(widget.songId);
      if (mounted) {
        setState(() {
          _songData = data;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  void _showTooltip(
    BuildContext context,
    Offset position,
    bool serverHas,
    bool clientHas,
  ) {
    _hideTooltip(); // Hide any existing tooltip

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + 42, // Position to the right of the checkmarks
        top: position.dy - 42, // Slightly above the touch point
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade700),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server availability line
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: serverHas
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Available on server',
                        style: TextStyle(
                          color: serverHas ? Colors.white : Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 0),
                  // Device availability line
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: clientHas
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Available on device',
                        style: TextStyle(
                          color: clientHas ? Colors.white : Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songId.isEmpty) {
      return const FileAvailabilityChecks(serverHas: false, clientHas: false);
    }

    final row = _songData;
    final clientHas =
        (row != null &&
        (row['on_device_status'] == 'true' ||
            row['on_device_status'] == true ||
            row['on_device_status'] == 1));
    final serverHas =
        (row != null &&
        ((row['file_exists'] == 'true' ||
                row['file_exists'] == true ||
                row['file_exists'] == 1) ||
            ((row['file_id'] ?? '').toString().isNotEmpty)));

    // Detect a true device-storage file (not a downloaded offline file)
    final isDeviceFile =
        (row != null &&
        ((row['is_device_file'] == 'true') || (row['is_device_file'] == true)));

    // If it's a device file, show only a themed storage icon with a custom tooltip
    if (isDeviceFile) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          // show custom tooltip with storage icon + label
          _hideTooltip();
          _overlayEntry = OverlayEntry(
            builder: (context) => Positioned(
              left: details.globalPosition.dx + 18,
              top: details.globalPosition.dy - 42,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Storage song',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          Overlay.of(context).insert(_overlayEntry!);
        },
        onTapUp: (_) => _hideTooltip(),
        onTapCancel: _hideTooltip,
        child: Icon(
          Icons.storage,
          size: widget.size,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque, // ensures the whole area is tappable
      onTapDown: (details) {
        _showTooltip(context, details.globalPosition, serverHas, clientHas);
      },
      onTapUp: (_) => _hideTooltip(),
      onTapCancel: _hideTooltip,

      // Optional: if you want the tooltip to follow the finger while dragging
      onPanStart: (details) {
        _showTooltip(context, details.globalPosition, serverHas, clientHas);
      },
      onPanEnd: (_) => _hideTooltip(),

      child: FileAvailabilityChecks(
        serverHas: serverHas,
        clientHas: clientHas,
        size: widget.size,
        spacing: widget.spacing,
      ),
    );
  }
}
