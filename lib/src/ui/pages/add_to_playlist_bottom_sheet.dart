import 'package:flutter/material.dart';
import '../../services/status_message_controller.dart';
import '../../services/playlists_service.dart';

class AddToPlaylistBottomSheet extends StatefulWidget {
  final String songId;
  final String? songTitle; // Optional for display

  const AddToPlaylistBottomSheet({
    super.key,
    required this.songId,
    this.songTitle,
  });

  @override
  State<AddToPlaylistBottomSheet> createState() =>
      _AddToPlaylistBottomSheetState();
}

class _AddToPlaylistBottomSheetState extends State<AddToPlaylistBottomSheet> {
  List<Map<String, dynamic>> _userPlaylists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPlaylists();
  }

  Future<void> _loadUserPlaylists() async {
    try {
      final allPlaylists = await PlaylistsService.getAllPlaylists();
      // Filter to only user-made playlists (not default ones)
      final userPlaylists = allPlaylists
          .where((playlist) => playlist['isDefault'] == false)
          .toList();

      if (mounted) {
        setState(() {
          _userPlaylists = userPlaylists;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AddToPlaylistBottomSheet: Error loading playlists: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addToPlaylist(String playlistId, String playlistName) async {
    try {
      await PlaylistsService.addSongToPlaylist(playlistId, widget.songId);

      if (mounted) {
        Navigator.of(context).pop();
        StatusMessageController.instance.showMessage(
          'Added to "$playlistName"',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      debugPrint('AddToPlaylistBottomSheet: Error adding to playlist: $e');
      if (mounted) {
        StatusMessageController.instance.showMessage(
          'Failed to add to playlist: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  Future<void> _showCreatePlaylistBottomSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreatePlaylistBottomSheet(),
    );

    if (result != null) {
      // Playlist was created, add song to it and refresh list
      await _addToPlaylist(result, 'new playlist');
      _loadUserPlaylists(); // Refresh the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Add to Playlist',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.songTitle != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      widget.songTitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Create new playlist option
          ListTile(
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 28,
              ),
            ),
            title: const Text('Create New Playlist'),
            subtitle: const Text('Make a new playlist for this song'),
            onTap: _showCreatePlaylistBottomSheet,
          ),

          const Divider(height: 1),

          // Playlists list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _userPlaylists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.queue_music,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No playlists yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your first playlist to get started',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _userPlaylists.length,
                    itemBuilder: (context, index) {
                      final playlist = _userPlaylists[index];
                      final playlistId = playlist['id'] as String;
                      final playlistName = playlist['name'] as String;
                      final songCount = playlist['songCount'] as int? ?? 0;

                      return ListTile(
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.queue_music,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(playlistName),
                        subtitle: Text('$songCount songs'),
                        onTap: () => _addToPlaylist(playlistId, playlistName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CreatePlaylistBottomSheet extends StatefulWidget {
  const CreatePlaylistBottomSheet({super.key});

  @override
  State<CreatePlaylistBottomSheet> createState() =>
      _CreatePlaylistBottomSheetState();
}

class _CreatePlaylistBottomSheetState extends State<CreatePlaylistBottomSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createPlaylist() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      StatusMessageController.instance.showMessage(
        'Please enter a playlist name',
        duration: const Duration(milliseconds: 1200),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final playlistId = await PlaylistsService.createPlaylist(name);
      if (mounted) {
        Navigator.of(context).pop(playlistId); // Return the new playlist ID
      }
    } catch (e) {
      debugPrint('CreatePlaylistBottomSheet: Error creating playlist: $e');
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
        StatusMessageController.instance.showMessage(
          'Failed to create playlist: $e',
          duration: const Duration(milliseconds: 1800),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              'Create Playlist',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Name input
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Playlist Name',
                hintText: 'Enter playlist name',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.queue_music),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createPlaylist(),
              autofocus: true,
            ),

            const SizedBox(height: 24),

            // Create button
            ElevatedButton(
              onPressed: _isCreating ? null : _createPlaylist,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCreating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Playlist'),
            ),

            const SizedBox(height: 16),

            // Cancel button
            TextButton(
              onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show the add to playlist bottom sheet
Future<void> showAddToPlaylistBottomSheet(
  BuildContext context,
  String songId, {
  String? songTitle,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        AddToPlaylistBottomSheet(songId: songId, songTitle: songTitle),
  );
}
