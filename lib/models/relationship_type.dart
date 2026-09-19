import 'entity_type.dart';

/// Canonical relationship types for v1 graph edges.
///
/// [located_in] stays on the venue entity as `located_in_entity_id`,
/// not as a relationships document.
enum RelationshipType {
  worksAt,
  clientOf,
  knows;

  String get firestoreValue {
    switch (this) {
      case RelationshipType.worksAt:
        return 'works_at';
      case RelationshipType.clientOf:
        return 'client_of';
      case RelationshipType.knows:
        return 'knows';
    }
  }

  String get label {
    switch (this) {
      case RelationshipType.worksAt:
        return 'Works at';
      case RelationshipType.clientOf:
        return 'Client of';
      case RelationshipType.knows:
        return 'Knows';
    }
  }

  /// Short verb for readable edge lines, e.g. "Tom works at Concorde 2".
  String get verb {
    switch (this) {
      case RelationshipType.worksAt:
        return 'works at';
      case RelationshipType.clientOf:
        return 'client of';
      case RelationshipType.knows:
        return 'knows';
    }
  }

  /// Entity types allowed as the *from* side when adding a link.
  List<EntityType> get allowedFromTypes {
    switch (this) {
      case RelationshipType.worksAt:
        return const [EntityType.person];
      case RelationshipType.clientOf:
        return const [EntityType.person, EntityType.client];
      case RelationshipType.knows:
        return const [EntityType.person];
    }
  }

  /// Entity types allowed as the *to* side.
  List<EntityType> get allowedToTypes {
    switch (this) {
      case RelationshipType.worksAt:
        return const [EntityType.org, EntityType.venue, EntityType.client];
      case RelationshipType.clientOf:
        return const [EntityType.org, EntityType.venue];
      case RelationshipType.knows:
        return const [EntityType.person];
    }
  }

  static const List<RelationshipType> all = RelationshipType.values;

  static RelationshipType? tryParse(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case 'works_at':
      case 'works at':
        return RelationshipType.worksAt;
      case 'client_of':
      case 'client of':
        return RelationshipType.clientOf;
      case 'knows':
        return RelationshipType.knows;
      default:
        return null;
    }
  }

  static RelationshipType parse(String? raw) =>
      tryParse(raw) ?? RelationshipType.knows;

  /// Types the user may create *from* this entity type.
  static List<RelationshipType> forSourceEntity(EntityType source) {
    return all.where((t) => t.allowedFromTypes.contains(source)).toList();
  }
}
