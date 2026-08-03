import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/search_history_item.dart';

/// Manages search history functionality
class SearchHistory {
  static const String _kSearchHistoryKey =
      'search_history_v2'; // Updated key for new format
  static const String _kLegacySearchHistoryKey =
      'search_history_v1'; // Legacy key
  static const int _maxHistoryItems = 50;

  /// Load search history from shared preferences
  static Future<List<SearchHistoryItem>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // Try to load new format first
      final newFormatData = sp.getStringList(_kSearchHistoryKey);
      if (newFormatData != null) {
        return newFormatData.map((jsonString) {
          try {
            final json = jsonDecode(jsonString) as Map<String, dynamic>;
            return SearchHistoryItem.fromJson(json);
          } catch (_) {
            // If parsing fails, treat as legacy string
            return SearchHistoryItem.fromString(jsonString);
          }
        }).toList();
      }

      // Fall back to legacy format
      final legacyData = sp.getStringList(_kLegacySearchHistoryKey);
      if (legacyData != null) {
        final items = legacyData
            .map((query) => SearchHistoryItem.fromString(query))
            .toList();
        // Migrate to new format
        await save(items);
        // Clean up legacy data
        await sp.remove(_kLegacySearchHistoryKey);
        return items;
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  /// Save search history to shared preferences
  static Future<void> save(List<SearchHistoryItem> history) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStrings = history
          .map((item) => jsonEncode(item.toJson()))
          .toList();
      await sp.setStringList(_kSearchHistoryKey, jsonStrings);
    } catch (_) {
      // Silently fail
    }
  }

  /// Add a query with filter type to search history
  /// Moves to front if already exists, adds to front if new
  /// Limits to maxHistoryItems
  static Future<void> addQuery(String query, {String? filterType}) async {
    if (query.trim().isEmpty) return;

    final history = await load();
    final newItem = SearchHistoryItem(
      query: query.trim(),
      filterType: filterType,
    );

    // Remove if exact same item exists
    history.removeWhere((item) => item == newItem);

    // Add to front
    history.insert(0, newItem);

    // Limit history size
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }

    await save(history);
  }

  /// Clear all search history
  static Future<void> clear() async {
    await save([]);
  }

  /// Filter history by query string (live filtering)
  static List<SearchHistoryItem> filterHistory(
    List<SearchHistoryItem> history,
    String typed,
  ) {
    if (typed.trim().isEmpty) return history;
    return history
        .where((item) => item.query.toLowerCase().contains(typed.toLowerCase()))
        .toList();
  }
}
