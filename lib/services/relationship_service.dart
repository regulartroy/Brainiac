import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/entity_type.dart';
import '../models/relationship_type.dart';

/// Helpers for reading/writing the `relationships` collection.
class RelationshipService {
  const RelationshipService({FirebaseFirestore? firestore})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Edges that involve [entityId] (by id) or [entityName] (by label fallback).
  static List<Map<String, dynamic>> edgesForEntity({
    required List<Map<String, dynamic>> relationships,
    required String entityId,
    String entityName = '',
  }) {
    final id = entityId.trim();
    final nameLower = entityName.trim().toLowerCase();
    return relationships.where((rel) {
      final fromId = (rel['from_entity_id'] ?? '').toString();
      final toId = (rel['to_entity_id'] ?? '').toString();
      if (id.isNotEmpty && (fromId == id || toId == id)) return true;
      if (nameLower.isEmpty) return false;
      final from = (rel['from_entity'] ?? '').toString().toLowerCase();
      final to = (rel['to_entity'] ?? '').toString().toLowerCase();
      return from == nameLower || to == nameLower;
    }).toList();
  }

  /// Human-readable line for an edge relative to [viewerId]/viewerName].
  static String readableLabel(
    Map<String, dynamic> rel, {
    required String viewerId,
    String viewerName = '',
  }) {
    final from = (rel['from_entity'] ?? '').toString();
    final to = (rel['to_entity'] ?? '').toString();
    final fromId = (rel['from_entity_id'] ?? '').toString();
    final toId = (rel['to_entity_id'] ?? '').toString();
    final typed = RelationshipType.tryParse(rel['type']?.toString());
    final verb = typed?.verb ??
        (rel['type'] ?? rel['summary'] ?? 'related').toString();

    final viewerIsFrom = (viewerId.isNotEmpty && fromId == viewerId) ||
        (viewerName.isNotEmpty &&
            from.toLowerCase() == viewerName.toLowerCase());
    final viewerIsTo = (viewerId.isNotEmpty && toId == viewerId) ||
        (viewerName.isNotEmpty &&
            to.toLowerCase() == viewerName.toLowerCase());

    if (viewerIsFrom) {
      return '$verb $to';
    }
    if (viewerIsTo) {
      return '$from $verb this';
    }
    return '$from $verb $to';
  }

  /// Targets eligible for [type], excluding the source itself.
  static List<Map<String, dynamic>> targetOptions({
    required RelationshipType type,
    required List<Map<String, dynamic>> allEntities,
    required String sourceId,
  }) {
    final allowed = type.allowedToTypes.toSet();
    final out = allEntities.where((e) {
      final id = (e['id'] ?? '').toString();
      if (id.isEmpty || id == sourceId) return false;
      return allowed.contains(EntityType.parse(e['type']?.toString()));
    }).toList()
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()),
      );
    return out;
  }

  Future<String> addLink({
    required String fromEntityId,
    required String fromEntity,
    required String toEntityId,
    required String toEntity,
    required RelationshipType type,
    List<String> labels = const [],
  }) async {
    final summary = '$fromEntity ${type.verb} $toEntity';
    final ref = await _db.collection('relationships').add({
      'from_entity_id': fromEntityId,
      'from_entity': fromEntity,
      'to_entity_id': toEntityId,
      'to_entity': toEntity,
      'type': type.firestoreValue,
      'summary': summary,
      if (labels.isNotEmpty) 'labels': labels,
      'last_updated': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> removeLink(String relationshipId) async {
    if (relationshipId.isEmpty) return;
    await _db.collection('relationships').doc(relationshipId).delete();
  }

  /// Set venue → area on the entity doc (not a relationships edge).
  Future<void> setLocatedIn({
    required String venueId,
    required String? areaId,
  }) async {
    await _db.collection('entities').doc(venueId).set({
      'located_in_entity_id': areaId ?? '',
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
