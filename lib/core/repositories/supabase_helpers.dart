/// Shared helpers for Supabase repository implementations.
///
/// Supabase Flutter (v2) can return:
///   • null        — when the query matches nothing
///   • Map         — when using .single() or for certain RPCs
///   • List<Map>   — the normal multi-row case
///
/// Using `(response as List)` throws a TypeError on web whenever the
/// SDK returns anything other than a List.  Use [asList] everywhere instead.
library supabase_helpers;

/// Safely converts a Supabase response to `List<Map<String, dynamic>>`.
/// Returns an empty list if the response is null or not a list.
List<Map<String, dynamic>> asList(dynamic response) {
  if (response == null) return [];
  if (response is List) {
    return response.cast<Map<String, dynamic>>();
  }
  // Single-row RPC returned a Map — wrap it.
  if (response is Map) {
    return [Map<String, dynamic>.from(response)];
  }
  return [];
}

/// Same as [asList] but preserves the raw `dynamic` items (no cast).
List<dynamic> asListDynamic(dynamic response) {
  if (response == null) return [];
  if (response is List) return response;
  if (response is Map) return [response];
  return [];
}
