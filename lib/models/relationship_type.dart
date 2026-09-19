import 'entity_type.dart';

/// Canonical relationship types for v1 graph edges.
///
/// [located_in] stays on the venue entity as `located_in_entity_id`,
/// not as a relationships document.
enum RelationshipType {
  freelancesFor,
  worksAt,
  clientOf,
  knows;

  String get firestoreValue {
    switch (this) {
      case RelationshipType.freelancesFor:
        return 'freelances_for';
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
      case RelationshipType.freelancesFor:
        return 'Freelances for';
      case RelationshipType.worksAt:
        return 'Works at';
      case RelationshipType.clientOf:
        return 'Client of';
      case RelationshipType.knows:
        return 'Knows';
    }
  }

  /// Short verb for readable edge lines, e.g. "Tom freelances for Concorde 2".
  String get verb {
    switch (this) {
      case RelationshipType.freelancesFor:
        return 'freelances for';
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
      case RelationshipType.freelancesFor:
        return const [EntityType.person];
      case RelationshipType.worksAt:
        return const [EntityType.person];
      case RelationshipType.clientOf:
        return const [EntityType.person, EntityType.client];
      case RelationshipType.knows:
        return const [EntityType.person];
    }
  }

  /// Entity types allowed as the *to* side.
  ///
  /// Role-client venues/orgs still have primary type venue/org, so they
  /// remain eligible via those types.
  List<EntityType> get allowedToTypes {
    switch (this) {
      case RelationshipType.freelancesFor:
        return const [EntityType.org, EntityType.venue, EntityType.client];
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
      case 'freelances_for':
      case 'freelances for':
      case 'freelance':
        return RelationshipType.freelancesFor;
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
  /// Order prefers freelances_for ahead of works_at for venue/client targets.
  static List<RelationshipType> forSourceEntity(EntityType source) {
    return all.where((t) => t.allowedFromTypes.contains(source)).toList();
  }

  /// Preferred default when adding a link from [source].
  /// Freelances-for is the default for people (venue/client freelance work).
  static RelationshipType defaultForSource(EntityType source) {
    final opts = forSourceEntity(source);
    if (opts.isEmpty) return RelationshipType.knows;
    return opts.first;
  }
}
