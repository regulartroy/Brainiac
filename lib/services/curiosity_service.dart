import '../models/entity_type.dart';

/// A single calm prompt to fill a missing graph blank.
class CuriosityQuestion {
  const CuriosityQuestion({
    required this.id,
    required this.entityId,
    required this.entityName,
    required this.entityType,
    required this.kind,
    required this.prompt,
    this.hint = '',
  });

  final String id;
  final String entityId;
  final String entityName;
  final EntityType entityType;

  /// One of: located_in | address | client_link
  final String kind;
  final String prompt;
  final String hint;

  Map<String, dynamic> toMap() => {
        'id': id,
        'entityId': entityId,
        'entityName': entityName,
        'entityType': entityType.firestoreValue,
        'kind': kind,
        'prompt': prompt,
        'hint': hint,
      };
}

/// Pure rule selection for the first-version curiosity panel.
///
/// Never solicits a person's home address.
class CuriosityService {
  const CuriosityService();

  /// Build a short queue (default max 5) of missing-blank questions.
  List<CuriosityQuestion> selectQuestions(
    List<Map<String, dynamic>> entities, {
    List<Map<String, dynamic>> relationships = const [],
    int maxQuestions = 5,
  }) {
    final byId = <String, Map<String, dynamic>>{};
    for (final e in entities) {
      final id = (e['id'] ?? '').toString();
      if (id.isNotEmpty) byId[id] = e;
    }

    final linkedClientIds = <String>{};
    for (final rel in relationships) {
      final fromId = (rel['from_entity_id'] ?? '').toString();
      final toId = (rel['to_entity_id'] ?? '').toString();
      final fromType = EntityType.parse(
        byId[fromId]?['type']?.toString() ??
            (rel['from_entity_type']?.toString()),
      );
      final toType = EntityType.parse(
        byId[toId]?['type']?.toString() ?? (rel['to_entity_type']?.toString()),
      );
      if (fromType == EntityType.client &&
          (toType == EntityType.org || toType == EntityType.venue)) {
        linkedClientIds.add(fromId);
      }
      if (toType == EntityType.client &&
          (fromType == EntityType.org || fromType == EntityType.venue)) {
        linkedClientIds.add(toId);
      }
    }

    final out = <CuriosityQuestion>[];

    for (final entity in entities) {
      if (out.length >= maxQuestions) break;
      final id = (entity['id'] ?? '').toString();
      final name = (entity['name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) continue;
      final type = EntityType.parse(entity['type']?.toString());
      final locatedIn = (entity['located_in_entity_id'] ?? '').toString().trim();
      final address = (entity['address'] ?? '').toString().trim();

      // Venue missing area link.
      if (type == EntityType.venue && locatedIn.isEmpty) {
        out.add(
          CuriosityQuestion(
            id: '$id:located_in',
            entityId: id,
            entityName: name,
            entityType: type,
            kind: 'located_in',
            prompt: 'Where is $name? (town/area)',
            hint: 'e.g. Brighton',
          ),
        );
        if (out.length >= maxQuestions) break;
      }

      // Venue / area missing address — never persons.
      if (type.isPlace && address.isEmpty) {
        out.add(
          CuriosityQuestion(
            id: '$id:address',
            entityId: id,
            entityName: name,
            entityType: type,
            kind: 'address',
            prompt: type == EntityType.venue
                ? 'What’s the address for $name?'
                : 'Any useful address or area note for $name?',
            hint: type == EntityType.venue
                ? 'Street / postcode if you travel there'
                : 'Optional — only if useful',
          ),
        );
        if (out.length >= maxQuestions) break;
      }

      // Client with no org/venue identity link.
      if (type == EntityType.client && !linkedClientIds.contains(id)) {
        out.add(
          CuriosityQuestion(
            id: '$id:client_link',
            entityId: id,
            entityName: name,
            entityType: type,
            kind: 'client_link',
            prompt: 'Which org or venue is $name tied to?',
            hint: 'Name of the organisation or venue',
          ),
        );
        if (out.length >= maxQuestions) break;
      }
    }

    return out.take(maxQuestions).toList();
  }
}
