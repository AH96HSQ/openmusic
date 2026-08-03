# Recommendations Page Implementation

## Overview
A new Recommendations page has been added to the app navigation, positioned between the Library and More pages.

## Features

### 1. Navigation
- New navigation icon with `Icons.auto_awesome` between Library and More
- Navigation index structure:
  - Index 0: Now Playing
  - Index 1: Library
  - Index 2: **Recommendations** (NEW)
  - Index 3: More

### 2. Page Layout

#### Most Played Section
- Displays the `MostPlayedWheel` widget at the top of the page
- Shows user's most frequently played songs

#### Recommendations Section
The section behavior depends on user's listening duration:

**Case 1: Insufficient Listening Time (< 20 minutes)**
- Displays a friendly card with:
  - Music note icon
  - "Keep Listening!" title
  - Message: "Listen to at least 20 minutes of Liked music to get personalized recommendations."
  - Current listening time display

**Case 2: Sufficient Listening Time (≥ 20 minutes)**
- Section header: "Your Recommendations"
- "Calculate Recommendations" button with:
  - Icon: `Icons.auto_awesome`
  - Loading state with spinner when calculating
  - Disabled state during calculation
- Recommendations list:
  - Empty state: "Tap the button above to get recommendations"
  - Ready for recommendation results (TODO: implementation pending)

### 3. Data Tracking

#### Database Enhancement
Added new method to `DatabaseHelper`:
```dart
Future<int> getTotalListeningDuration()
```
- Calculates total `play_time` for all liked songs
- Returns duration in seconds
- Filters by `liked_status IN (1, '1', 'true')`

### 4. User Experience
- Page loads with a loading spinner while fetching listening duration
- Smooth transition between insufficient/sufficient time states
- Clear call-to-action for recommendation calculation
- Responsive to theme changes (dark/light mode)

## Technical Details

### Files Created
- `lib/src/pages/recommendations_page.dart` - Main recommendations page

### Files Modified
- `lib/src/main_scaffold.dart` - Added recommendations page to navigation
- `lib/src/data/database_helper.dart` - Added `getTotalListeningDuration()` method

### State Management
- `_isLoadingDuration`: Loading state for fetching listening time
- `_totalListeningDuration`: Total seconds of music listened (for liked songs)
- `_isCalculating`: Loading state during recommendation calculation
- `_recommendations`: List to store calculated recommendations

### Thresholds
- **Minimum listening time**: 20 minutes (1200 seconds)
- Calculated from `play_time` of all liked songs in the database

## Next Steps (TODO)
1. Implement recommendation calculation algorithm in `_calculateRecommendations()`
2. Design recommendation result UI (list items with artwork, title, artist)
3. Add interaction handlers for recommendation items (play, add to playlist, etc.)
4. Implement backend API endpoint for recommendation generation if needed
5. Add error handling for recommendation calculation failures
6. Consider adding refresh/recalculate functionality
7. Add analytics tracking for recommendation engagement

## Design Rationale
- **Most Played at top**: Shows user their listening patterns
- **20-minute threshold**: Ensures sufficient data for meaningful recommendations
- **Clear messaging**: Encourages engagement when insufficient data
- **Progressive disclosure**: Only show calculation button when ready
- **Consistent styling**: Follows app's Material Design 3 theme
