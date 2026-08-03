# Last.fm Integration for Music Recommendations

## Overview
OpenMusic now uses **Last.fm API** for music recommendations instead of ReccoBeats. The integration maintains the same recommendation algorithm but leverages Last.fm's extensive music database and similarity data.

## Last.fm Credentials
- **Application Name**: OpenMusic
- **API Key**: `c49f9c122a1bf16453ae347fe4758e7e`
- **Shared Secret**: `6289df83bfb4e3b61eb4481e5015fe08`
- **Registered to**: openmusic96

## Architecture

### Backend (Node.js/TypeScript)
The recommendation system now runs **server-side** for better security and performance:

```
Flutter App → Backend API → Last.fm API → Spotify Search → Flutter App
```

### New Files Created

#### 1. `Backend/src/services/lastfm.service.ts`
Service class that handles Last.fm API interactions:
- `getSimilarTracks(artist, track, limit)` - Fetches similar tracks from Last.fm
- Uses Last.fm's `track.getSimilar` method
- Returns track metadata including artist names and match scores

#### 2. `Backend/src/routes/recommendations.ts`
Express route that processes recommendation requests:
- **Endpoint**: `POST /v1/recommendations/similar`
- **Input**: Array of core songs with quotas
- **Output**: Array of recommended tracks with Spotify IDs

**Request Format**:
```json
{
  "coreSongs": [
    {
      "id": "spotify_track_id",
      "title": "Song Title",
      "artists": "Artist Name",
      "quota": 5
    }
  ]
}
```

**Response Format**:
```json
{
  "recommendations": [
    {
      "id": "spotify_track_id",
      "title": "Recommended Song",
      "artists": "Artist Name",
      "score": 0.95
    }
  ],
  "total": 20
}
```

### Modified Files

#### 1. `Backend/.env`
Added Last.fm credentials:
```properties
LASTFM_API_KEY=c49f9c122a1bf16453ae347fe4758e7e
LASTFM_SHARED_SECRET=6289df83bfb4e3b61eb4481e5015fe08
```

#### 2. `Backend/src/app.ts`
Registered new recommendations route:
```typescript
import recommendationsRouter from "./routes/recommendations";
app.use("/v1/recommendations", recommendationsRouter);
```

#### 3. `lib/src/services/recommendation_service.dart`
Updated Flutter service to use backend endpoint:
- Removed direct ReccoBeats API calls
- Now sends core songs to backend endpoint
- Backend handles Last.fm API calls and Spotify ID resolution
- Increased timeout to 30 seconds for server processing

## Recommendation Algorithm

The algorithm remains unchanged:

### 🎧 Daily Recommendation Flow

1. **Filter Qualified Songs**
   - Get all liked songs from database
   - Filter songs with play_time > 0

2. **Compute Weights**
   - Calculate normalized weight based on listening duration
   - Higher play time = higher weight

3. **Select Top 5 Core Songs**
   - Sort by weight (descending)
   - Take top 5 songs

4. **Distribute 20 Recommendation Slots**
   - Allocate slots proportionally based on weights
   - Each core song gets 1-20 slots

5. **Fetch Similar Tracks (Last.fm)**
   - For each core song, query Last.fm API
   - Convert Last.fm results to Spotify track IDs
   - Filter out tracks already in user's library

6. **Handle Shortfalls**
   - If fewer than 20 tracks found, request more
   - Increase quota by 5 per core song

7. **Finalize & Shuffle**
   - Shuffle to mix variety
   - Return exactly 20 tracks (or fewer if unavailable)

## API Differences: ReccoBeats vs Last.fm

### ReccoBeats (Old)
- **Endpoint**: `GET /v1/track/recommendation`
- **Input**: Spotify track ID
- **Output**: List of similar tracks with Spotify IDs
- **Pros**: Direct Spotify ID mapping
- **Cons**: Less reliable, limited database

### Last.fm (New)
- **Endpoint**: `GET /track.getSimilar`
- **Input**: Artist name + Track name
- **Output**: List of similar tracks with metadata
- **Pros**: Extensive database, better similarity scores
- **Cons**: Requires additional Spotify search step

## Server-Side Benefits

Moving recommendations to the backend provides:

1. **Security**: API keys never exposed to client
2. **Performance**: Batch processing of multiple songs
3. **Reliability**: Better error handling and retries
4. **Scalability**: Easier to add caching or rate limiting
5. **Maintainability**: Single point to update API logic

## Testing

### Backend Testing
```powershell
# Start backend server
cd Backend
npm run dev

# Test recommendations endpoint
curl -X POST http://localhost:5002/v1/recommendations/similar `
  -H "Content-Type: application/json" `
  -d '{
    "coreSongs": [
      {
        "id": "3n3Ppam7vgaVa1iaRUc9Lp",
        "title": "Mr. Brightside",
        "artists": "The Killers",
        "quota": 10
      }
    ]
  }'
```

### Flutter Testing
The existing recommendation flow works without changes:
1. Open app
2. Like some songs
3. Play them to accumulate listening time
4. Navigate to Recommendations tab
5. Wait for recommendations to load

## Error Handling

### Last.fm API Errors
- **404**: Track not found - Skip and continue
- **400**: Invalid request - Log and continue
- **Rate Limit**: Automatic retry with delay

### Spotify Search Errors
- If track not found on Spotify, skip it
- No impact on overall recommendation count

### Backend Errors
- Flutter service catches all errors
- Logs detailed error messages
- Falls back gracefully with empty recommendations

## Future Enhancements

1. **Caching**: Cache Last.fm results to reduce API calls
2. **Multiple Seeds**: Send multiple tracks to Last.fm at once
3. **Hybrid Approach**: Combine Last.fm + Spotify recommendations
4. **User Preferences**: Allow users to tune recommendation diversity
5. **Scrobbling**: Track user listening to Last.fm for better personalization

## Dependencies

### Backend
- `axios` - Already installed for HTTP requests
- No additional packages needed

### Flutter
- `dio` - Already in use for HTTP requests
- No changes needed

## Deployment Notes

1. Ensure `.env` file contains Last.fm credentials
2. Backend must be running for recommendations to work
3. Flutter app needs valid `BACKEND_BASE_URL` in `.env`
4. No changes to database schema required

## Support

Last.fm API Documentation:
- https://www.last.fm/api/intro
- https://www.last.fm/api/show/track.getSimilar

OpenMusic Backend:
- Location: `Backend/`
- Port: 5002 (default)
- Logs: Check terminal for detailed request/response logs
