class EntityRecord {
  const EntityRecord({
    required this.name,
    required this.type,
    required this.summary,
    this.id = '',
  });

  final String id;
  final String name;
  final String type;
  final String summary;

  factory EntityRecord.fromMap(Map<String, dynamic> map, {String id = ''}) {
    return EntityRecord(
      id: id,
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'concept',
      summary: map['summary']?.toString() ?? '',
    );
  }
}

class EntityGroup {
  const EntityGroup({
    required this.canonicalName,
    required this.type,
    required this.names,
  });

  final String canonicalName;
  final String type;
  final List<String> names;
}

class LinkedEntitiesRewrite {
  const LinkedEntitiesRewrite({
    required this.linkedEntities,
    required this.linkedEntityIds,
    required this.changed,
  });

  final List<String> linkedEntities;
  final List<String> linkedEntityIds;
  final bool changed;
}

class RelationshipRewrite {
  const RelationshipRewrite({
    required this.fromEntity,
    required this.toEntity,
    required this.fromEntityId,
    required this.toEntityId,
    required this.type,
    required this.drop,
    required this.changed,
    required this.edgeKey,
  });

  final String fromEntity;
  final String toEntity;
  final String fromEntityId;
  final String toEntityId;
  final String type;
  final bool drop;
  final bool changed;
  final String edgeKey;
}

class PruningService {
  static String normalizeEntityKey(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  static String canonicalizeName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String entityIdForName(String name) {
    return canonicalizeName(name)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  // Keep private aliases used by existing call sites / tests via instance methods.
  String _normalizeEntityKey(String value) => normalizeEntityKey(value);

  String _canonicalizeName(String value) => canonicalizeName(value);

  List<EntityGroup> groupDuplicateEntities(List<EntityRecord> entities) {
    final grouped = <String, List<EntityRecord>>{};

    for (final entity in entities) {
      final key = _normalizeEntityKey(entity.name);
      if (key.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(key, () => <EntityRecord>[]).add(entity);
    }

    final result = grouped.entries.where((entry) => entry.value.length > 1).map(
      (entry) {
        final records = entry.value.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

        final canonicalName = _canonicalizeName(records.first.name);

        return EntityGroup(
          canonicalName: canonicalName,
          type: records.first.type,
          names: records.map((record) => record.name).toList(),
        );
      },
    ).toList();

    result.sort((a, b) => a.canonicalName.compareTo(b.canonicalName));
    return result;
  }

  /// Rewrite action-item entity name/id lists when aliases merge into [canonicalName]/[canonicalId].
  LinkedEntitiesRewrite rewriteLinkedEntities({
    required List<String> linkedEntities,
    required List<String> linkedEntityIds,
    required Set<String> aliasNames,
    required Set<String> aliasIds,
    required String canonicalName,
    required String canonicalId,
  }) {
    final aliasKeys = aliasNames
        .map(normalizeEntityKey)
        .where((key) => key.isNotEmpty)
        .toSet();

    final names = <String>[];
    var changed = false;

    for (final value in linkedEntities) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        changed = true;
        continue;
      }
      if (aliasKeys.contains(normalizeEntityKey(trimmed))) {
        if (!names.contains(canonicalName)) {
          names.add(canonicalName);
        }
        if (trimmed != canonicalName) changed = true;
      } else if (!names.contains(trimmed)) {
        names.add(trimmed);
      } else {
        changed = true;
      }
    }
    if (names.length !=
        linkedEntities.where((value) => value.trim().isNotEmpty).length) {
      changed = true;
    }

    final ids = <String>[];
    for (final value in linkedEntityIds) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        changed = true;
        continue;
      }
      if (aliasIds.contains(trimmed)) {
        if (!ids.contains(canonicalId)) {
          ids.add(canonicalId);
        }
        if (trimmed != canonicalId) changed = true;
      } else if (!ids.contains(trimmed)) {
        ids.add(trimmed);
      } else {
        changed = true;
      }
    }
    if (ids.length !=
        linkedEntityIds.where((value) => value.trim().isNotEmpty).length) {
      changed = true;
    }

    return LinkedEntitiesRewrite(
      linkedEntities: names,
      linkedEntityIds: ids,
      changed: changed,
    );
  }

  /// Remap a relationship edge through alias name/id maps. Self-loops are dropped.
  RelationshipRewrite rewriteRelationship({
    required String fromEntity,
    required String toEntity,
    required String fromEntityId,
    required String toEntityId,
    required String type,
    required Map<String, String> canonicalNameByKey,
    required Map<String, String> canonicalIdByAlias,
  }) {
    var fromName = fromEntity.trim();
    var toName = toEntity.trim();
    var fromId = fromEntityId.trim();
    var toId = toEntityId.trim();
    final edgeType = type.trim().isEmpty ? 'related' : type.trim();
    var changed = false;

    final fromKey = normalizeEntityKey(fromName);
    final toKey = normalizeEntityKey(toName);
    if (fromKey.isNotEmpty && canonicalNameByKey.containsKey(fromKey)) {
      final next = canonicalNameByKey[fromKey]!;
      if (next != fromName) {
        fromName = next;
        changed = true;
      }
    }
    if (toKey.isNotEmpty && canonicalNameByKey.containsKey(toKey)) {
      final next = canonicalNameByKey[toKey]!;
      if (next != toName) {
        toName = next;
        changed = true;
      }
    }
    if (fromId.isNotEmpty && canonicalIdByAlias.containsKey(fromId)) {
      final next = canonicalIdByAlias[fromId]!;
      if (next != fromId) {
        fromId = next;
        changed = true;
      }
    }
    if (toId.isNotEmpty && canonicalIdByAlias.containsKey(toId)) {
      final next = canonicalIdByAlias[toId]!;
      if (next != toId) {
        toId = next;
        changed = true;
      }
    }

    final fromNorm = normalizeEntityKey(fromName);
    final toNorm = normalizeEntityKey(toName);
    final drop = fromName.isEmpty ||
        toName.isEmpty ||
        fromNorm == toNorm ||
        (fromId.isNotEmpty && toId.isNotEmpty && fromId == toId);

    return RelationshipRewrite(
      fromEntity: fromName,
      toEntity: toName,
      fromEntityId: fromId,
      toEntityId: toId,
      type: edgeType,
      drop: drop,
      changed: changed,
      edgeKey: '$fromNorm|$toNorm|${normalizeEntityKey(edgeType)}',
    );
  }

  List<String> buildDailyQuestions(List<EntityRecord> entities) {
    final uniqueEntities = entities
        .where((entity) => entity.name.trim().isNotEmpty)
        .toList();

    if (uniqueEntities.isEmpty) {
      return const <String>[];
    }

    final pairCandidates = <String>[];
    for (var i = 0; i < uniqueEntities.length; i++) {
      for (var j = i + 1; j < uniqueEntities.length; j++) {
        final left = uniqueEntities[i];
        final right = uniqueEntities[j];
        pairCandidates.add('${left.name}::${right.name}');
      }
    }

    if (pairCandidates.isEmpty) {
      return const <String>[];
    }

    final questionCount = pairCandidates.length < 5 ? pairCandidates.length : 5;
    final questions = <String>[];

    for (var i = 0; i < questionCount; i++) {
      final pair = pairCandidates[i].split('::');
      final first = pair[0];
      final second = pair[1];
      questions.add('What next step connects $first and $second?');
    }

    return questions;
  }

  List<Map<String, dynamic>> compressTodoList(
    List<Map<String, dynamic>> tasks,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final task in tasks) {
      final description = (task['description'] ?? '').toString().trim();
      if (description.isEmpty) continue;

      final linkedEntities =
          ((task['linked_entities'] as List<dynamic>?) ?? const [])
              .whereType<String>()
              .map((entity) => entity.trim())
              .where((entity) => entity.isNotEmpty)
              .toList();

      final primaryEntity = linkedEntities.isNotEmpty
          ? linkedEntities.first
          : _guessEntityFromDescription(description);
      final key = primaryEntity.isEmpty
          ? '__untagged__${description.toLowerCase()}'
          : _normalizeEntityKey(primaryEntity);

      final existing = grouped.putIfAbsent(
        key,
        () => {
          'description': primaryEntity.isEmpty ? description : description,
          'linked_entities': primaryEntity.isEmpty
              ? const <String>[]
              : [primaryEntity],
          'status': task['status']?.toString() ?? 'open',
          '_count': 0,
          '_examples': <String>[] as List<String>,
        },
      );

      existing['_count'] = ((existing['_count'] as int?) ?? 0) + 1;
      final examples = (existing['_examples'] as List<String>?) ?? <String>[];
      examples.add(description);
      existing['_examples'] = examples;
      if (linkedEntities.isNotEmpty &&
          !((existing['linked_entities'] as List<String>).contains(
            primaryEntity,
          ))) {
        existing['linked_entities'] = [primaryEntity];
      }
    }

    final result = grouped.values.map((entry) {
      final count = (entry['_count'] as int?) ?? 1;
      final examples = (entry['_examples'] as List<String>? ?? const <String>[])
          .toList();
      final entity =
          ((entry['linked_entities'] as List<String>?) ?? const <String>[])
              .firstOrNull;
      final summaryEntity =
          entity ?? _guessEntityFromDescription(examples.first);
      final baseDescription = examples.isEmpty
          ? (entry['description'] ?? '').toString()
          : examples.first;
      final description = count > 1
          ? '$count tasks for ${summaryEntity.isNotEmpty ? summaryEntity : 'this focus'}: ${examples.take(2).join(' • ')}'
          : baseDescription;

      return {
        'description': description,
        'linked_entities': summaryEntity.isNotEmpty
            ? [summaryEntity]
            : const <String>[],
        'status': entry['status']?.toString() ?? 'open',
        'compressed': true,
      };
    }).toList();

    result.sort((a, b) {
      final aCount = ((a['description'] as String).split(' ').first.isEmpty)
          ? 0
          : int.tryParse((a['description'] as String).split(' ').first) ?? 1;
      final bCount = ((b['description'] as String).split(' ').first.isEmpty)
          ? 0
          : int.tryParse((b['description'] as String).split(' ').first) ?? 1;
      return bCount.compareTo(aCount);
    });

    return result;
  }

  String _guessEntityFromDescription(String description) {
    final matches = RegExp(
      r'\b(?:with|for|about|to|at)\s+([A-Z][A-Za-z0-9\-\. ]+?)\b(?:\?|\.|$)',
    ).allMatches(description);
    for (final match in matches) {
      final candidate = match.group(1)?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }

    final words = description.split(RegExp(r'\s+'));
    final nameParts = <String>[];
    for (final word in words) {
      if (word.isEmpty) continue;
      if (word.startsWith(RegExp(r'[A-Z]'))) {
        nameParts.add(word.replaceAll(RegExp(r'[^A-Za-z0-9\-\. ]'), ''));
      }
    }
    return nameParts.isEmpty ? '' : nameParts.join(' ');
  }
}
