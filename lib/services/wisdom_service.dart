class InsightCard {
  const InsightCard({
    required this.summary,
    required this.connections,
    required this.advice,
  });

  final String summary;
  final List<String> connections;
  final List<String> advice;
}

class DailyBriefing {
  const DailyBriefing({
    required this.headline,
    required this.summary,
    required this.priorities,
  });

  final String headline;
  final String summary;
  final List<String> priorities;
}

class GraphNode {
  const GraphNode({
    required this.label,
    required this.weight,
    required this.kind,
  });

  final String label;
  final int weight;
  final String kind;
}

class GraphSummary {
  const GraphSummary({
    required this.nodes,
    required this.connections,
    required this.summary,
  });

  final List<GraphNode> nodes;
  final List<String> connections;
  final String summary;
}

class CalendarEntry {
  const CalendarEntry({
    required this.title,
    required this.client,
    required this.category,
    required this.place,
    required this.startsAt,
  });

  final String title;
  final String client;
  final String category;
  final String place;
  final DateTime? startsAt;

  Map<String, dynamic> toJson() => {
    'title': title,
    'client': client,
    'category': category,
    'place': place,
    'startsAt': startsAt?.toIso8601String(),
  };
}

class RoutePlan {
  const RoutePlan({
    required this.stopCount,
    required this.totalMinutes,
    required this.summary,
    required this.stops,
  });

  final int stopCount;
  final int totalMinutes;
  final String summary;
  final List<String> stops;
}

class QuestionAnswer {
  const QuestionAnswer({required this.answer, required this.highlights});

  final String answer;
  final List<String> highlights;
}

class WisdomService {
  InsightCard compileInsight({
    required List<String> entityNames,
    required List<String> openTasks,
  }) {
    final uniqueEntities = entityNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final groupedEntityCounts = <String, int>{};
    for (final entity in uniqueEntities) {
      groupedEntityCounts[entity] = (groupedEntityCounts[entity] ?? 0) + 1;
    }

    final uniqueEntitiesSet = groupedEntityCounts.keys.toList();
    final uniqueTasks = openTasks
        .map((task) => task.trim())
        .where((task) => task.isNotEmpty)
        .toSet()
        .toList();

    final summary = uniqueTasks.isEmpty
        ? 'No active tasks remain in motion.'
        : '${uniqueTasks.length} active tasks remain in motion across ${uniqueEntitiesSet.length} entities.';

    final connections = uniqueEntitiesSet.isEmpty
        ? const <String>[]
        : uniqueEntitiesSet.asMap().entries.map((entry) {
            final index = entry.key;
            final entity = entry.value;
            final task = uniqueTasks.isEmpty
                ? 'No current action is attached.'
                : uniqueTasks[index % uniqueTasks.length];

            return '• $entity is connected to: $task';
          }).toList();

    final advice = <String>[];
    for (final entry in groupedEntityCounts.entries) {
      if (entry.value <= 1) continue;
      advice.add(
        'Advice: ${entry.key} has ${entry.value} open tasks; batch them into a single follow-up message or combined action.',
      );
    }

    if (advice.isEmpty && uniqueTasks.length > 1) {
      advice.add(
        'Advice: keep the highest-leverage task in view and compress the remaining work into a single next-step batch.',
      );
    }

    if (advice.isEmpty && uniqueTasks.length == 1) {
      advice.add(
        'Advice: keep this task visible until it is completed, then prune the context behind it.',
      );
    }

    return InsightCard(
      summary: summary,
      connections: connections,
      advice: advice,
    );
  }

  DailyBriefing compileDailyBriefing({
    required List<String> entityNames,
    required List<String> openTasks,
  }) {
    final uniqueEntities = entityNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    final uniqueTasks = openTasks
        .map((task) => task.trim())
        .where((task) => task.isNotEmpty)
        .toSet()
        .toList();

    final focusEntity = uniqueEntities.isEmpty
        ? 'your system'
        : uniqueEntities.first;

    final headline = uniqueTasks.isEmpty
        ? 'No active focus right now.'
        : '$focusEntity is the current focus.';

    final summary = uniqueTasks.isEmpty
        ? 'No clear priorities remain in the active memory stream.'
        : 'Daily focus: keep the highest-leverage work in front of you and batch the rest into a single follow-up.';

    final priorities = <String>[];

    for (final task in uniqueTasks.take(3)) {
      if (uniqueEntities.isEmpty) {
        priorities.add('• $task');
      } else {
        final entity =
            uniqueEntities[uniqueTasks.indexOf(task) % uniqueEntities.length];
        priorities.add('• $entity: $task');
      }
    }

    if (priorities.isEmpty) {
      priorities.add('• Nothing is active right now.');
    }

    return DailyBriefing(
      headline: headline,
      summary: summary,
      priorities: priorities,
    );
  }

  GraphSummary compileKnowledgeGraph({
    required List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> entities = const [],
    List<Map<String, dynamic>> relationships = const [],
  }) {
    final counts = <String, int>{};
    final entityKinds = <String, String>{};
    final connections = <String>[];

    for (final entity in entities) {
      final name = (entity['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
      entityKinds[name] = (entity['type'] ?? 'entity').toString();
    }

    for (final relationship in relationships) {
      final from = (relationship['from_entity'] ?? '').toString().trim();
      final to = (relationship['to_entity'] ?? '').toString().trim();
      if (from.isEmpty || to.isEmpty) continue;
      counts[from] = (counts[from] ?? 0) + 1;
      counts[to] = (counts[to] ?? 0) + 1;
      final pair = [from, to]..sort();
      connections.add('${pair[0]} ↔ ${pair[1]}');
    }

    for (final task in tasks) {
      final description = (task['description'] ?? '').toString().trim();
      final entities = (task['linked_entities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      if (description.isEmpty && entities.isEmpty) continue;

      for (final entity in entities) {
        counts[entity] = (counts[entity] ?? 0) + 1;
        entityKinds[entity] = entityKinds[entity] ?? 'entity';
      }

      if (entities.length >= 2) {
        final ordered = entities.toSet().toList();
        for (int i = 0; i < ordered.length; i++) {
          for (int j = i + 1; j < ordered.length; j++) {
            final pair = [ordered[i], ordered[j]]..sort();
            connections.add('${pair[0]} ↔ ${pair[1]}');
          }
        }
      }
    }

    final nodes =
        counts.entries
            .map(
              (entry) => GraphNode(
                label: entry.key,
                weight: entry.value,
                kind: entityKinds[entry.key] ?? 'entity',
              ),
            )
            .toList()
          ..sort((a, b) => b.weight.compareTo(a.weight));

    final summary = nodes.isEmpty
        ? 'No active connections yet. Add a note or task and Brainiac will infer the links.'
        : 'Brainiac sees ${nodes.length} connected entities and ${connections.length} meaningful links.';

    return GraphSummary(
      nodes: nodes.take(6).toList(),
      connections: connections.take(5).toList(),
      summary: summary,
    );
  }

  List<CalendarEntry> compileCalendar({
    required List<Map<String, dynamic>> tasks,
    DateTime? now,
  }) {
    final referenceNow = now ?? DateTime.now();
    final entries = <CalendarEntry>[];
    final seenDescriptions = <String>{};

    for (final task in tasks) {
      final description = (task['description'] ?? '').toString().trim();
      final normalizedDescription = description
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      final isPersonAdd =
          RegExp(
            r'\b(add|create|save|remember)\b',
            caseSensitive: false,
          ).hasMatch(description) &&
          RegExp(
            r'\bas\s+a?\s*person\b',
            caseSensitive: false,
          ).hasMatch(description);
      if (isPersonAdd ||
          normalizedDescription.isEmpty ||
          !seenDescriptions.add(normalizedDescription)) {
        continue;
      }
      final linked = (task['linked_entities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final category = (task['category'] ?? task['type'] ?? 'General')
          .toString()
          .trim();
      final client = (task['client'] ?? linked.firstOrNull ?? 'Independent')
          .toString()
          .trim();
      final place = (task['place'] ?? 'Location TBD').toString().trim();
      final startAtRaw =
          task['startAt'] ?? task['scheduledAt'] ?? task['dueDate'];
      final startsAt = startAtRaw is String && startAtRaw.isNotEmpty
          ? DateTime.tryParse(startAtRaw)
          : null;

      entries.add(
        CalendarEntry(
          title: description,
          client: client,
          category: category,
          place: place,
          startsAt: startsAt ?? referenceNow,
        ),
      );
    }

    entries.sort((a, b) {
      final left = a.startsAt ?? DateTime.now();
      final right = b.startsAt ?? DateTime.now();
      return left.compareTo(right);
    });

    return entries;
  }

  RoutePlan estimateRoutePlan({
    required List<CalendarEntry> entries,
    int averageTravelMinutes = 15,
  }) {
    final activeEntries = entries
        .where((entry) => entry.place.isNotEmpty)
        .toList();
    final orderedStops = activeEntries.map((entry) => entry.place).toList();
    final uniqueStops = orderedStops.toSet().toList();
    final totalMinutes = (activeEntries.length * averageTravelMinutes).clamp(
      0,
      600,
    );

    final summary = activeEntries.isEmpty
        ? 'No route data available yet; add places to start calculating travel.'
        : '${activeEntries.length} stops planned for the day with roughly ${totalMinutes} minutes of travel overhead.';

    return RoutePlan(
      stopCount: activeEntries.length,
      totalMinutes: totalMinutes,
      summary: summary,
      stops: uniqueStops,
    );
  }

  QuestionAnswer answerQuestion({
    required String question,
    required List<Map<String, dynamic>> tasks,
  }) {
    final q = question.trim();
    if (q.isEmpty) {
      return const QuestionAnswer(
        answer: 'I can help once you ask me what to look at next.',
        highlights: ['No question asked'],
      );
    }

    final lowerQuestion = q.toLowerCase();
    final candidateTasks = tasks.where((task) {
      final description = (task['description'] ?? '').toString().toLowerCase();
      final entities = (task['linked_entities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((name) => name.toLowerCase())
          .toList();
      return description.contains(lowerQuestion) ||
          entities.any((entity) => lowerQuestion.contains(entity));
    }).toList();

    final clientTasks = tasks.where((task) {
      final entities = (task['linked_entities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      return entities.any(
        (entity) => lowerQuestion.contains(entity.toLowerCase()),
      );
    }).toList();

    final relevant = (clientTasks.isNotEmpty ? clientTasks : candidateTasks)
        .take(3);
    final highlights = relevant.map((task) {
      final description = (task['description'] ?? '').toString();
      final category = (task['category'] ?? 'General').toString();
      final place = (task['place'] ?? 'Location TBD').toString();
      return '$category • $description • $place';
    }).toList();

    if (highlights.isEmpty) {
      return const QuestionAnswer(
        answer:
            'I do not see a clear match in the active memory. I can help refine it once you add the client or project name.',
        highlights: ['No clear match'],
      );
    }

    final entityNames = (clientTasks.isNotEmpty ? clientTasks : candidateTasks)
        .expand(
          (task) => (task['linked_entities'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty),
        )
        .toSet()
        .toList();
    final clientLabel = entityNames.isNotEmpty
        ? entityNames.join(', ')
        : 'that client or project';

    final answer = clientTasks.isNotEmpty
        ? 'You have ${clientTasks.length} active items tied to $clientLabel, and the strongest focus is here.'
        : 'I can see ${candidateTasks.length} relevant memory entries. The strongest matches are below.';

    return QuestionAnswer(answer: answer, highlights: highlights);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
