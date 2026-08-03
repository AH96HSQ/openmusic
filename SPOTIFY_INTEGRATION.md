# Spotify Integration Guide

## Overview

This document describes the Spotify integration implementation for OpenMusic. The integration allows users to authenticate with their Spotify account and import all their playlists and liked songs into the OpenMusic database.

## Architecture

### Components

1. **SpotifyService** (`lib/src/services/spotify_service.dart`)
   - Handles OAuth 2.0 PKCE authentication flow
   - Manages access/refresh tokens
   - Imports playlists and liked songs from Spotify API
   - Reusable singleton service

2. **SpotifyCallbackPage** (`lib/src/ui/pages/spotify_callback_page.dart`)
   - Handles the OAuth callback redirect
   - Processes authentication response
   - Triggers data import
   - Shows progress to user

3. **MainActivity** (`android/app/src/main/kotlin/com/openmusic/app/MainActivity.kt`)
   - Handles deep link intents
   - Routes deep links to Flutter via MethodChannel

4. **main.dart** - Enhanced with:
   - SpotifyService initialization
   - Deep link listener setup
   - Navigation to callback page

## Authentication Flow

### 1. User Initiates Authentication

When user taps "Import from Spotify!" button in the More page:

```dart
await SpotifyService.instance.authenticate();
```

### 2. OAuth PKCE Flow

The service:
- Generates a code verifier and challenge (PKCE)
- Generates a random state parameter
- Opens browser with Spotify authorization URL
- User logs in and authorizes the app

### 3. Callback Handling

Spotify redirects to: `openmusic://spotify-callback?code=...&state=...`

Android deep link intent is caught by MainActivity, which:
- Receives the intent
- Sends it to Flutter via MethodChannel
- Flutter navigates to SpotifyCallbackPage

### 4. Token Exchange

SpotifyCallbackPage:
- Validates the state parameter
- Extracts authorization code
- Exchanges code for access/refresh tokens
- Stores tokens in SharedPreferences

### 5. Data Import

After successful authentication:
- Imports all user's liked songs
- Imports all user's playlists (including songs)
- Shows progress updates
- Returns to app when complete

## API Endpoints Used

### Authentication
- `https://accounts.spotify.com/authorize` - OAuth authorization
- `https://accounts.spotify.com/api/token` - Token exchange/refresh

### Data Fetching
- `GET /v1/me/tracks` - User's liked songs
- `GET /v1/me/playlists` - User's playlists
- `GET /v1/playlists/{id}/tracks` - Songs in a playlist

## Scopes Required

The app requests the following Spotify scopes:
- `user-library-read` - Read liked songs
- `playlist-read-private` - Read private playlists
- `playlist-read-collaborative` - Read collaborative playlists

## Configuration

### Environment Variables (.env)

```properties
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
SPOTIFY_MARKET=US
```

### Spotify Developer Dashboard

1. Go to https://developer.spotify.com/dashboard
2. Create/edit your app
3. Add redirect URI: `openmusic://spotify-callback`
4. Copy Client ID and Client Secret to .env

### Android Manifest

The following intent filter is added to handle deep links:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="openmusic"
        android:host="spotify-callback" />
</intent-filter>
```

## Database Integration

### Song Storage

Imported songs are stored with:
- `id`: `spotify_{spotify_track_id}`
- `source`: `spotify`
- `spotify_uri`: `spotify:track:{id}`
- `spotify_url`: External Spotify URL
- `liked_status`: `true` for liked songs
- All metadata (title, artists, album, duration, artwork)

### Playlist Storage

- Playlist IDs: `spotify_{spotify_playlist_id}`
- Songs maintain their order via position field
- Playlists can be updated on subsequent imports

## Usage Example

```dart
// Initialize service (done in main.dart)
await SpotifyService.instance.initialize();

// Start authentication flow
await SpotifyService.instance.authenticate();
// User completes login in browser...
// App handles callback automatically

// Check authentication status
if (SpotifyService.instance.isAuthenticated) {
  // Import data manually (also done automatically after auth)
  await SpotifyService.instance.importSpotifyData(
    onProgress: (message) {
      print(message);
    },
  );
}

// Logout
await SpotifyService.instance.logout();
```

## Error Handling

The service handles:
- Network errors
- Invalid credentials
- Expired tokens (auto-refresh)
- Missing songs in playlists
- Outlook email blocking
- Invalid state parameters

Errors are shown to user via StatusMessageController.

## Token Management

- Access tokens expire after 1 hour
- Refresh tokens are long-lived
- Tokens are automatically refreshed before API calls
- Tokens persist across app restarts via SharedPreferences

## Security Features

- PKCE (Proof Key for Code Exchange) for secure OAuth
- State parameter validation to prevent CSRF attacks
- Secure random string generation
- Client credentials stored in .env (not in code)

## Testing

To test the integration:

1. Ensure .env has valid Spotify credentials
2. Run the app
3. Go to More page
4. Tap "Import from Spotify!"
5. Login to Spotify in browser
6. Authorize the app
7. Watch import progress
8. Check that songs/playlists appear in app

## Limitations

- Only imports metadata (no audio files)
- Requires active Spotify account
- Rate limited by Spotify API
- Playlists with many songs may take time to import

## Future Enhancements

Possible improvements:
- Incremental sync (only import new songs)
- Sync periodically in background
- Import playback history
- Import followed artists
- Two-way sync (export from OpenMusic to Spotify)
- iOS support for deep links

## Troubleshooting

### "Not authenticated" error
- Check that SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET are set
- Verify redirect URI in Spotify Dashboard matches `openmusic://spotify-callback`

### Deep link not working
- Check AndroidManifest.xml has the intent filter
- Verify MainActivity is properly handling intents
- Test with: `adb shell am start -d "openmusic://spotify-callback?code=test&state=test"`

### Token refresh fails
- Tokens may have been revoked
- User needs to re-authenticate
- Check network connectivity

### Import fails
- Check API rate limits
- Verify network connection
- Check for null/deleted tracks in playlists
- Review error messages in debug console
