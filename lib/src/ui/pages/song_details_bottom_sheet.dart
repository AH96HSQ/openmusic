import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../data/database_helper.dart';

/// Shows detailed song information from the database
Future<void> showSongDetailsBottomSheet(
  BuildContext context,
  String songId,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      final height = MediaQuery.of(ctx).size.height * 0.8;
      return SizedBox(
        height: height,
        child: _SongDetailsContent(songId: songId),
      );
    },
  );
}

class _SongDetailsContent extends StatefulWidget {
  final String songId;

  const _SongDetailsContent({required this.songId});

  @override
  State<_SongDetailsContent> createState() => _SongDetailsContentState();
}

class _SongDetailsContentState extends State<_SongDetailsContent> {
  Map<String, dynamic>? _songData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSongData();
  }

  Future<void> _loadSongData() async {
    try {
      final data = await DatabaseHelper.instance.getSong(widget.songId);
      if (mounted) {
        setState(() {
          _songData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'Song Details',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      'Error loading song details:\n$_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                )
              : _songData == null
              ? const Center(child: Text('Song not found'))
              : _buildSongDetails(theme),
        ),
      ],
    );
  }

  Widget _buildSongDetails(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Basic Info Section
        _buildSection(theme, 'Basic Information', Icons.music_note, [
          _buildInfoRow(theme, 'Song ID', widget.songId, canCopy: true),
          _buildInfoRow(theme, 'Title', _songData!['title'] ?? 'N/A'),
          _buildInfoRow(theme, 'Album', _songData!['album'] ?? 'N/A'),
          _buildInfoRow(
            theme,
            'Artists',
            _formatArtists(_songData!['artists']),
          ),
          _buildInfoRow(
            theme,
            'Duration',
            _formatDuration(_songData!['durationMs']),
          ),
        ]),

        const SizedBox(height: 20),

        // File Information
        _buildSection(theme, 'File Information', Icons.folder, [
          _buildInfoRow(
            theme,
            'Local File',
            _songData!['filePath'] != null ? 'Yes' : 'No',
          ),
          if (_songData!['filePath'] != null)
            _buildInfoRow(
              theme,
              'File Path',
              _songData!['filePath'],
              canCopy: true,
            ),
          _buildInfoRow(
            theme,
            'File Size',
            _formatFileSize(_songData!['sizeBytes']),
          ),
          _buildInfoRow(
            theme,
            'Server Available',
            _songData!['serverFileAvailable'] == 1 ? 'Yes' : 'No',
          ),
        ]),

        const SizedBox(height: 20),

        // External Data
        if (_songData!['ext'] != null) ...[
          _buildSection(theme, 'External Data', Icons.link, [
            _buildExpandableJson(theme, 'Spotify Data', _songData!['ext']),
          ]),
          const SizedBox(height: 20),
        ],

        // Artwork
        if (_songData!['artwork'] != null) ...[
          _buildSection(theme, 'Artwork', Icons.image, [
            _buildExpandableJson(theme, 'Artwork Data', _songData!['artwork']),
          ]),
          const SizedBox(height: 20),
        ],

        // Metadata
        _buildSection(theme, 'Metadata', Icons.data_object, [
          _buildInfoRow(
            theme,
            'Date Added',
            _formatDate(_songData!['dateAdded']),
          ),
          _buildInfoRow(
            theme,
            'Last Modified',
            _formatDate(_songData!['dateModified']),
          ),
          _buildInfoRow(
            theme,
            'Play Count',
            _songData!['playCount']?.toString() ?? '0',
          ),
        ]),

        const SizedBox(height: 20),

        // Raw JSON
        _buildSection(theme, 'Raw JSON Data', Icons.code, [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Full Database Record',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => _copyToClipboard(
                        const JsonEncoder.withIndent('  ').convert(_songData),
                        'JSON data',
                      ),
                      tooltip: 'Copy JSON',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(_songData),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String? value, {
    bool canCopy = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value ?? 'N/A',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (canCopy && value != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyToClipboard(value, label),
                    tooltip: 'Copy',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableJson(ThemeData theme, String label, dynamic jsonData) {
    String jsonString;
    try {
      if (jsonData is String) {
        final parsed = jsonDecode(jsonData);
        jsonString = const JsonEncoder.withIndent('  ').convert(parsed);
      } else {
        jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      }
    } catch (e) {
      jsonString = jsonData.toString();
    }

    return ExpansionTile(
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.all(8),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyToClipboard(jsonString, label),
                    tooltip: 'Copy JSON',
                  ),
                ],
              ),
              SelectableText(
                jsonString,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatArtists(dynamic artists) {
    if (artists == null) return 'N/A';
    if (artists is String) {
      try {
        final parsed = jsonDecode(artists);
        if (parsed is List) {
          return parsed.join(', ');
        }
        return artists;
      } catch (e) {
        return artists;
      }
    }
    if (artists is List) {
      return artists.join(', ');
    }
    return artists.toString();
  }

  String _formatDuration(dynamic durationMs) {
    if (durationMs == null) return 'N/A';
    final ms = durationMs is int
        ? durationMs
        : int.tryParse(durationMs.toString());
    if (ms == null) return 'N/A';

    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(dynamic sizeBytes) {
    if (sizeBytes == null) return 'N/A';
    final bytes = sizeBytes is int
        ? sizeBytes
        : int.tryParse(sizeBytes.toString());
    if (bytes == null) return 'N/A';

    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime date;
      if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'N/A';
      }
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp.toString();
    }
  }
}
