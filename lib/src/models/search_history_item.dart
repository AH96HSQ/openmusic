/// Model for search history items that includes filter conditions
class SearchHistoryItem {
  final String query;
  final String?
  filterType; // 'artist', 'album', 'track', or null for general search

  const SearchHistoryItem({required this.query, this.filterType});

  /// Create from JSON map
  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return SearchHistoryItem(
      query: json['query'] as String,
      filterType: json['filterType'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {'query': query, 'filterType': filterType};
  }

  /// Create from legacy string format (for backward compatibility)
  factory SearchHistoryItem.fromString(String query) {
    return SearchHistoryItem(query: query);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchHistoryItem &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          filterType == other.filterType;

  @override
  int get hashCode => query.hashCode ^ filterType.hashCode;

  @override
  String toString() =>
      'SearchHistoryItem{query: $query, filterType: $filterType}';
}
