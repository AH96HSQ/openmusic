# ListenBrainz Similar Songs Finder

## Overview
This script converts ISRC codes to MBIDs (MusicBrainz IDs) and attempts to find similar songs using the ListenBrainz API.

## Current Status
✅ **API Working**: The script successfully connects to the ListenBrainz Labs API.  
⚠️ **Dataset Issue**: The similarity dataset appears to be unpopulated or limited as of October 14, 2025.

### Working Endpoint:
`https://labs.api.listenbrainz.org/similar-recordings?recording_mbids={mbid}&algorithm={algo}`

The API responds with 200 OK but returns empty `recordings` arrays for tested songs (including very popular tracks like "Bohemian Rhapsody").

## Implementation

### Files Created:
- **`src/scripts/findSimilarSongs.ts`**: Main script with ISRC→MBID conversion and similar song lookup
- **`src/scripts/testListenBrainz.ts`**: Simple test script to verify API endpoint

### Features Implemented:
✅ ISRC to MBID conversion via MusicBrainz API
✅ Song metadata lookup (title, artist, MBID)
✅ Similar song API request structure
✅ Error handling and debug logging
✅ Formatted console output

### How It Works:
```typescript
// 1. Convert ISRC to MBID
const mbid = await isrcToMbid('GBAAA8900033');
// Returns: 'bdbf97db-9949-450c-9871-932f3d27aed6'

// 2. Find similar songs (currently returns 404)
const similar = await findSimilarSongs(mbid);
// Expected to return: Array of similar tracks with score, name, artist
```

## Usage

### Run the script:
```bash
cd Backend
npm run find-similar
```

### Expected Output (once API works):
```
═══════════════════════════════════════════════
  ListenBrainz Similar Songs Finder
═══════════════════════════════════════════════

🔍 Looking up ISRC: GBAAA8900033
✓ Found: "Song Title" by Artist Name
  MBID: bdbf97db-9949-450c-9871-932f3d27aed6

🎵 Finding similar songs for MBID: ...
✓ Found 50 similar songs:
───────────────────────────────────────────────
1. "Similar Song 1" by Artist 1
   Score: 0.9234 | MBID: xxx-yyy-zzz

2. "Similar Song 2" by Artist 2
   Score: 0.8891 | MBID: aaa-bbb-ccc
...
```

## Possible Solutions

### 1. Check ListenBrainz Documentation
The API might have moved or changed. Check:
- https://listenbrainz.readthedocs.io/
- https://github.com/metabrainz/listenbrainz-server

### 2. API Authentication
The endpoint might require:
- User token
- API key
- OAuth authentication

### 3. Alternative APIs
Consider these alternatives:
- **Spotify API**: Has recommendations endpoint
- **Last.fm API**: Similar artists/tracks
- **AcousticBrainz**: Audio features for similarity
- **ReccoBeats**: Already explored (works but different features)

### 4. Contact ListenBrainz
Ask on their forums or IRC:
- IRC: #musicbrainz on irc.libera.chat
- Forums: https://community.metabrainz.org/

## API Response Format (Expected)

Based on the ChatGPT example, the API should return:
```json
{
  "payload": {
    "recordings": [
      {
        "recording_mbid": "xxx-yyy-zzz",
        "recording_name": "Song Title",
        "artist_name": "Artist Name",
        "score": 0.9234,
        "artist_mbid": "aaa-bbb-ccc"
      }
    ]
  }
}
```

## Findings

### What Works:
✅ ISRC → MBID conversion via MusicBrainz API  
✅ API endpoint connection (`labs.api.listenbrainz.org`)  
✅ Proper request/response handling  
✅ Error handling and logging  

### What Doesn't Work:
❌ Similarity dataset returns empty results for all tested songs  
❌ Even very popular songs (Bohemian Rhapsody, etc.) return 0 similar recordings  

### Possible Reasons:
1. **Dataset not populated yet**: ListenBrainz Labs may still be building the similarity dataset
2. **Requires specific songs**: Only certain songs in their training set have similarity data
3. **Algorithm mismatch**: The algorithm parameter might need to be updated
4. **Dataset location**: Similarity data might be hosted elsewhere

## Next Steps

1. **Contact ListenBrainz**: Ask about similarity dataset status on their forums
2. **Alternative algorithms**: Try different algorithm parameters if available
3. **Check documentation**: Look for updated ListenBrainz Labs docs
4. **Alternative solution**: Implement Spotify recommendations API as primary solution

## Related Files
- `package.json`: Added `find-similar` script command
- `src/scripts/findSimilarSongs.ts`: Main implementation
- `src/scripts/testListenBrainz.ts`: API endpoint testing

## Dependencies
- `axios`: HTTP client for API requests
- `tsx`: TypeScript execution for scripts
