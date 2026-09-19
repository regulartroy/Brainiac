import 'entity_type.dart';

/// Facet roles on an entity (orthogonal to primary [EntityType]).
///
/// Example: a venue that is also a freelance client keeps `type: venue`
/// and `roles: ['client']` — one node, dual meaning.
class EntityRoles {
  const EntityRoles._();

  static const String client = 'client';

  /// Canonical role values recognised today (extensible).
  static const List<String> known = [client];

  /// Normalize a Firestore `roles` field into a clean list of strings.
  static List<String> parse(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final s = item.toString().trim().toLowerCase();
      if (s.isEmpty) continue;
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  static bool has(Map<String, dynamic> entity, String role) {
    return parse(entity['roles']).contains(role.trim().toLowerCase());
  }

  static bool hasClientRole(Map<String, dynamic> entity) =>
      has(entity, client);

  /// True when primary type is client, or roles includes client.
  static bool isClientFacet(Map<String, dynamic> entity) {
    if (EntityType.parse(entity['type']?.toString()) == EntityType.client) {
      return true;
    }
    return hasClientRole(entity);
  }

  /// Types that may toggle the "Also a client" facet in the editor.
  static bool canToggleClientRole(EntityType type) {
    return type == EntityType.venue ||
        type == EntityType.org ||
        type == EntityType.person;
  }

  /// Add or remove [role] from an existing roles list.
  static List<String> withRole(
    List<String> current, {
    required String role,
    required bool enabled,
  }) {
    final r = role.trim().toLowerCase();
    final next = List<String>.from(current);
    if (enabled) {
      if (!next.contains(r)) next.add(r);
    } else {
      next.remove(r);
    }
    return next;
  }
}
