# OpenMusic Backend

A music search backend compatible with the original OpenMusic API, running on port 5002.

## Features

- **Search API**: `/v1/search` - Search for music tracks via Spotify
- **MongoDB Integration**: Stores results in `openmusic` database
- **File Tracking**: Tracks downloaded files and their availability
- **API Compatibility**: Maintains compatibility with existing frontend clients

## Setup

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Configure Environment**:
   Copy `.env.example` to `.env` and update the values:
   ```bash
   cp .env.example .env
   ```
   
   Update these values in `.env`:
   - `SPOTIFY_CLIENT_ID` - Your Spotify app client ID
   - `SPOTIFY_CLIENT_SECRET` - Your Spotify app client secret
   - `MONGODB_URI` - MongoDB connection string (defaults to local openmusic database)

3. **Start MongoDB** (if running locally):
   ```bash
   mongod
   ```

4. **Run Development Server**:
   ```bash
   npm run dev
   ```

The server will start on `http://localhost:5002`

## API Endpoints

### General Search
```
GET /v1/search?q=artist%20song&limit=20&offset=0&market=US
```

### Artist-Specific Search
```
GET /v1/search/artist?q=metallica&limit=20&offset=0&market=US
```

### Album-Specific Search
```
GET /v1/search/album?q=master%20of%20puppets&limit=20&offset=0&market=US
```

### Title-Specific Search
```
GET /v1/search/title?q=enter%20sandman&limit=20&offset=0&market=US
```

**Parameters** (same for all search endpoints):
- `q` (required) - Search query
- `limit` (optional) - Results limit (default: 20, max: 50)
- `offset` (optional) - Results offset (default: 0)
- `market` (optional) - Spotify market (default: US)

### Album Details
```
GET /v1/album/:id?market=US
```

**Parameters**:
- `id` (required) - Spotify album ID
- `market` (optional) - Spotify market (default: US)

### Artist Details
```
GET /v1/artist/:id
```

**Parameters**:
- `id` (required) - Spotify artist ID

### Artist Top Tracks
```
GET /v1/artist/:id/top-tracks?market=US
```

**Parameters**:
- `id` (required) - Spotify artist ID
- `market` (optional) - Spotify market (default: US)

### Artist Albums
```
GET /v1/artist/:id/albums?limit=20&offset=0&include_groups=album,single&market=US
```

**Parameters**:
- `id` (required) - Spotify artist ID
- `limit` (optional) - Results limit (default: 20, max: 50)
- `offset` (optional) - Results offset (default: 0)
- `include_groups` (optional) - Album types to include (default: "album,single")
- `market` (optional) - Spotify market (default: US)

### Track Details with Navigation IDs
```
GET /v1/track/:id/details?market=US
```

**Parameters**:
- `id` (required) - Spotify track ID
- `market` (optional) - Spotify market (default: US)

This endpoint enriches track data with album and artist IDs for easy navigation. It:
1. Checks if the track is already in the database with IDs
2. If not, fetches from Spotify and saves the enriched data
3. Returns the track with navigation IDs for accessing album/artist details

## Database Storage

The API caches **track data only** to the MongoDB `openmusic` database for performance, while keeping albums and artists always fresh from Spotify:

### **What Gets Saved** 💾
- ✅ **Search results** → Tracks saved to `songs` collection
- ✅ **Album tracks** → All tracks from albums saved to `songs` collection  
- ✅ **Artist top tracks** → Top tracks saved to `songs` collection
- ✅ **Track details** → Enriched with navigation IDs

### **What Stays Fresh** 🔄
- 🌐 **Album details** → Always fetched fresh from Spotify
- 🌐 **Artist details** → Always fetched fresh from Spotify  
- 🌐 **Artist albums list** → Always fetched fresh from Spotify

### **Why This Approach?**
- **Tracks** change rarely → Safe to cache for performance
- **Albums/Artists** can have updated info → Always get latest data
- **Best of both worlds** → Fast track access + fresh metadata

## Download System 📥

### **Download Endpoint**
```
POST /v1/files/download
```

**Request Body:**
```json
{
  "songId": "spotify_track_id",
  "url": "https://music-source.com/track.mp3",
  "source": "spotify"
}
```

**Response:**
```json
{
  "ok": true,
  "file": {
    "_id": "670123456789abcdef012345",
    "songId": "4iV5W9uYEdYUVa79Axb7Rhh",
    "source": "spotify", 
    "originUrl": "https://music-source.com/track.mp3",
    "status": "pending",
    "createdAt": "2025-10-10T12:00:00.000Z"
  }
}
```

### **File Status Tracking**
```
GET /v1/files/:id
```
Returns file metadata and current status (`pending`, `ready`, `failed`)

### **Real-time Progress**
```
GET /v1/files/:id/progress
```
Server-Sent Events (SSE) endpoint for live download progress updates

**Progress Events:**
```javascript
// Initial status
{ "meta": { "id": "...", "status": "pending" } }

// Progress updates  
{ "written": 1024000, "total": 5120000 }

// Completion
{ "written": 5120000, "total": 5120000, "done": true }

// Errors
{ "error": "Download failed", "done": true }
```

### **Download Priority System** 🎯

**For Spotify URLs:**
1. 🚀 **RapidAPI** (Primary) → High-quality, fast downloads
2. 🔄 **Fallback Methods** → 3 legacy methods as backup
   - SpotMate (URL return)
   - FabDL (URL return) 
   - SpotiMP3 (Direct file)

**For Generic URLs:**
- 🌐 **Generic Downloader** → Standard HTTP downloads

### **Download Features** ✨
- 🔄 **Duplicate Prevention** → Same URL won't download twice
- 📊 **Progress Tracking** → Real-time updates via SSE
- 🗂️ **Organized Storage** → Files stored in dated directories  
- 🔁 **Auto Retry** → Missing files automatically re-download
- 🎯 **Smart Detection** → Spotify vs generic download strategies
- 🛡️ **Resilient System** → Multiple fallback methods ensure success

## Streaming System 🎵

### **Stream Audio Files**
```
GET /v1/stream/:id
```
**Features:**
- 🎵 **HTTP Range Support** → Partial content (206) for seeking
- 📱 **Mobile/Browser Compatible** → Works with HTML5 audio players
- 🔄 **Auto Re-download** → Missing files automatically re-downloaded
- 📊 **Bandwidth Efficient** → Only streams requested byte ranges

### **File Lookup by Song**
```
GET /v1/files/by-song/:songId
```
**Responses:**
- `200` → File ready and available
- `404` → No file found, start download
- `409` → Download in progress, subscribe to progress

**Example Response:**
```json
{
  "ok": true,  
  "file": {
    "_id": "670123456789abcdef012345",
    "songId": "4iV5W9uYEdYUVa79Axb7Rh",
    "status": "ready",
    "path": "/uploads/data/2025/10/10/file.mp3",
    "sizeBytes": 5120000
  },
  "resolution": "direct"
}
```

### **Streaming Workflow** 🔄
```
1. Check if file exists: GET /v1/files/by-song/:songId
2. If 404: Start download: POST /v1/files/download  
3. If 409: Wait for completion: GET /v1/files/:id/progress
4. When ready: Stream audio: GET /v1/stream/:id
```

## System Monitoring 📊

### **Complete System Info**
```
GET /v1/system/info
```
**Response includes:**
- 🧠 **Memory** → Total/Used/Free RAM + usage percentage
- ⚡ **CPU** → Model, cores, speed, current usage percentage  
- 💾 **Storage** → All drives with total/used/free + usage percentages
- 🖥️ **System** → Platform, hostname, uptime, load average
- 🎵 **Database** → Songs count, downloaded files, success rates

### **Formatted System Info**
```
GET /v1/system/info/formatted
```
Same data but with human-readable formatting (GB, MB, hours, etc.)

### **Individual Components**
```
GET /v1/system/memory    → RAM information only
GET /v1/system/cpu       → CPU information only  
GET /v1/system/storage   → Storage information only
GET /v1/system/database  → Database statistics only
GET /v1/system/health    → Health status with alerts
```

### **Example Response** 📋
```json
{
  "ok": true,
  "system": {
    "timestamp": "2025-10-10T15:30:45.123Z",
    "memory": {
      "total": 17179869184,
      "used": 8589934592,
      "free": 8589934592, 
      "usagePercent": 50
    },
    "cpu": {
      "model": "Intel(R) Core(TM) i7-10700K",
      "cores": 16,
      "speed": 3800,
      "currentUsage": 25
    },
    "storage": {
      "drives": [
        {
          "drive": "C:",
          "total": 500107862016,
          "used": 250053931008,
          "free": 250053931008,
          "usagePercent": 50
        }
      ],
      "totalStorage": 500107862016,
      "totalUsed": 250053931008,
      "totalFree": 250053931008,
      "totalUsagePercent": 50
    },
    "database": {
      "totalSongs": 1250,
      "downloadedFiles": 856,
      "readyFiles": 798,
      "pendingFiles": 12,
      "failedFiles": 46
    }
  }
}
```

### **Health Monitoring** 🏥
```
GET /v1/system/health
```
**Status Levels:**
- 🟢 **healthy** → All systems normal
- 🟡 **warning** → High usage (>85% RAM, >90% storage)
- 🔴 **critical** → Very high usage (>90% CPU)

**Example Health Response:**
```json
{
  "ok": true,
  "status": "healthy",
  "alerts": [],
  "summary": {
    "memory": "50%",
    "cpu": "25%", 
    "storage": "50%",
    "uptime": "2d 5h 30m",
    "songs": "1,250",
    "downloads": "798"
  }
}
```

**Response** (General Search):
```json
{
  "query": "artist song",
  "searchType": "general",
  "market": "US",
  "page": {
    "offset": 0,
    "limit": 20,
    "returned": 15,
    "totalFetched": 15
  },
  "counts": {
    "localFetched": 0,
    "spotifyFetched": 15
  },
  "results": [
    {
      "source": "spotify",
      "title": "Song Title",
      "album": "Album Name",
      "artists": ["Artist Name"],
      "durationMs": 180000,
      "artwork": {...},
      "ext": {...},
      "_id": "spotify_track_id",
      "file": {
        "exists": false
      }
    }
  ]
}
```

**Response** (Field-Specific Search):
```json
{
  "query": "metallica",
  "searchField": "artist",
  "searchType": "artist",
  "market": "US",
  "page": {...},
  "counts": {...},
  "results": [...]
}
```

### Health Check
```
GET /health
```

Returns server status and uptime information.

## Project Structure

```
src/
├── app.ts              # Express app configuration
├── server.ts           # Server startup
├── clients/
│   └── spotify.ts      # Spotify API client
├── db/
│   └── mongo.ts        # MongoDB connection
├── mappers/
│   └── spotifyMapper.ts # Spotify to internal format mapping
├── models/
│   ├── Song.ts         # Song data model
│   └── FileAsset.ts    # File asset model
├── routes/
│   └── search.ts       # Search API routes
├── types/
│   └── music.ts        # TypeScript type definitions
└── utils/
    ├── normalize.ts    # String normalization utilities
    └── normKey.ts      # Normalization key generation
```

## Development

- `npm run dev` - Start development server with hot reload
- `npm run build` - Build for production
- `npm run start` - Start production server
- `npm run typecheck` - Type check without building