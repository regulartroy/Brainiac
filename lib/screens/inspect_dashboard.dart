import 'package:flutter/material.dart';

import '../services/wisdom_service.dart';

/// Thin, mostly read-only inspect surface over the live life graph.
///
/// Shows counts + browse tabs for entities, relationships, appointments
/// (dated action_items), and attention/priorities from existing signals.
/// Does not add capture, curation, or bot-execution features.
class InspectDashboardPage extends StatefulWidget {
  const InspectDashboardPage({
    super.key,
    required this.entities,
    required this.relationships,
    required this.tasks,
    required this.wisdomService,
  });

  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> relationships;
  final List<Map<String, dynamic>> tasks;
  final WisdomService wisdomService;

  @override
  State<InspectDashboardPage> createState() => _InspectDashboardPageState();
}

class _InspectDashboardPageState extends State<InspectDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _entityTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _openTasks => widget.tasks.where((task) {
        final status = (task['status'] ?? 'open').toString();
        return status != 'done' && status != 'archived';
      }).toList();

  List<CalendarEntry> get _appointments =>
      widget.wisdomService.compileCalendar(tasks: widget.tasks);

  List<Map<String, dynamic>> get _attentionEntities {
    return widget.entities.where((entity) {
      final status =
          (entity['attention_status'] ?? 'unknown').toString().toLowerCase();
      return status == 'active' ||
          status == 'waiting' ||
          status == 'needs_attention' ||
          status == 'priority';
    }).toList();
  }

  Map<String, int> get _entityTypeCounts {
    final counts = <String, int>{};
    for (final entity in widget.entities) {
      final type = (entity['type'] ?? 'concept').toString();
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, dynamic>> get _filteredEntities {
    if (_entityTypeFilter == 'all') return widget.entities;
    return widget.entities
        .where(
          (e) =>
              (e['type'] ?? 'concept').toString().toLowerCase() ==
              _entityTypeFilter.toLowerCase(),
        )
        .toList();
  }

  Map<String, dynamic> _entityForLabel(String label) {
    final lower = label.toLowerCase();
    for (final entity in widget.entities) {
      final name = (entity['name'] ?? '').toString();
      if (name.toLowerCase() == lower) return entity;
    }
    return {
      'id': '',
      'name': label,
      'type': 'entity',
      'summary': '',
      'attention_status': 'unknown',
      'current_focus': '',
    };
  }

  List<Map<String, dynamic>> _linkedTasksFor(String label) {
    final lower = label.toLowerCase();
    return _openTasks.where((task) {
      final links = (task['linked_entities'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().toLowerCase());
      return links.contains(lower);
    }).toList();
  }

  List<Map<String, dynamic>> _edgesFor(String label) {
    final lower = label.toLowerCase();
    return widget.relationships.where((rel) {
      final from = (rel['from_entity'] ?? '').toString().toLowerCase();
      final to = (rel['to_entity'] ?? '').toString().toLowerCase();
      return from == lower || to == lower;
    }).toList();
  }

  void _openEntityDetail(BuildContext context, String label) {
    final entity = _entityForLabel(label);
    final linkedTasks = _linkedTasksFor(label);
    final edges = _edgesFor(label);
    final summary = (entity['summary'] ?? '').toString();
    final focus = (entity['current_focus'] ?? '').toString();
    final status = (entity['attention_status'] ?? 'unknown').toString();
    final type = (entity['type'] ?? 'entity').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        type == 'person'
                            ? Icons.person_outline
                            : Icons.hub_outlined,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entity['name'].toString(),
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(label: Text(status)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(type),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(summary),
                  ],
                  if (focus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Focus: $focus'),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Linked actions (${linkedTasks.length})',
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (linkedTasks.isEmpty)
                    const Text('No open linked actions.')
                  else
                    ...linkedTasks.take(12).map(
                          (task) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• ${task['description']}'),
                          ),
                        ),
                  const SizedBox(height: 16),
                  Text(
                    'Relationships (${edges.length})',
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (edges.isEmpty)
                    const Text('No related edges.')
                  else
                    ...edges.take(12).map((rel) {
                      final from = (rel['from_entity'] ?? '').toString();
                      final to = (rel['to_entity'] ?? '').toString();
                      final relType = (rel['type'] ??
                              rel['description'] ??
                              'related')
                          .toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $from → $to ($relType)'),
                      );
                    }),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _countChip(BuildContext context, String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.surfaceContainerHighest,
      label: Text('$label: $count'),
    );
  }

  Widget _buildCountsStrip(BuildContext context) {
    final typeCounts = _entityTypeCounts;
    final typeParts = typeCounts.entries
        .map((e) => '${e.key} ${e.value}')
        .join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live graph',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _countChip(context, 'Entities', widget.entities.length),
                _countChip(
                  context,
                  'Relationships',
                  widget.relationships.length,
                ),
                _countChip(context, 'Open actions', _openTasks.length),
                _countChip(context, 'Appointments', _appointments.length),
                _countChip(context, 'Attention', _attentionEntities.length),
              ],
            ),
            if (typeParts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'By type: $typeParts',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntitiesTab() {
    final types = ['all', ..._entityTypeCounts.keys.toList()..sort()];
    final entities = _filteredEntities;

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: types.map((type) {
              final selected = _entityTypeFilter == type;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(type),
                  selected: selected,
                  onSelected: (_) => setState(() => _entityTypeFilter = type),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: entities.isEmpty
              ? const Center(child: Text('No entities in this filter.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entity = entities[index];
                    final name = (entity['name'] ?? '').toString();
                    final type = (entity['type'] ?? 'concept').toString();
                    final status =
                        (entity['attention_status'] ?? 'unknown').toString();
                    final summary = (entity['summary'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          type == 'person'
                              ? Icons.person_outline
                              : Icons.hub_outlined,
                        ),
                        title: Text(name),
                        subtitle: Text(
                          summary.isEmpty
                              ? '$type · $status'
                              : '$type · $status · $summary',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openEntityDetail(context, name),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRelationshipsTab() {
    final rels = widget.relationships;
    if (rels.isEmpty) {
      return const Center(child: Text('No relationships yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final rel = rels[index];
        final from = (rel['from_entity'] ?? '').toString();
        final to = (rel['to_entity'] ?? '').toString();
        final relType =
            (rel['type'] ?? rel['description'] ?? 'related').toString();
        return Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.link),
            title: Text('$from → $to'),
            subtitle: Text(relType, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: from.isEmpty ? null : () => _openEntityDetail(context, from),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentsTab() {
    final entries = _appointments;
    if (entries.isEmpty) {
      return const Center(
        child: Text('No scheduled appointments (items with startAt).'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final endSuffix = entry.endsAt == null
            ? ''
            : '–${entry.endsAt!.hour.toString().padLeft(2, '0')}:${entry.endsAt!.minute.toString().padLeft(2, '0')}';
        final when =
            '${entry.startsAt.year}-${entry.startsAt.month.toString().padLeft(2, '0')}-${entry.startsAt.day.toString().padLeft(2, '0')} '
            '${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}$endSuffix';
        final place =
            entry.place.isEmpty ? 'Place: (not set)' : 'Place: ${entry.place}';
        final linked = entry.linkedEntityIds.isEmpty
            ? ''
            : ' · ${entry.linkedEntityIds.join(', ')}';
        return Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.event),
            title: Text(entry.title),
            subtitle: Text('$when · $place$linked'),
            onTap: entry.linkedEntityIds.isEmpty
                ? null
                : () =>
                    _openEntityDetail(context, entry.linkedEntityIds.first),
          ),
        );
      },
    );
  }

  Widget _buildPrioritiesTab() {
    final openDescriptions = _openTasks
        .map((t) => (t['description'] ?? '').toString())
        .where((d) => d.isNotEmpty)
        .toList();
    final entityNames = widget.entities
        .map((e) => (e['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toList();
    final briefing = widget.wisdomService.compileDailyBriefing(
      entityNames: entityNames,
      openTasks: openDescriptions,
    );
    final attention = _attentionEntities;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Priority signals',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(briefing.headline),
                const SizedBox(height: 4),
                Text(
                  briefing.summary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...briefing.priorities.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Active attention (${attention.length})',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (attention.isEmpty)
          const Card(
            child: ListTile(
              dense: true,
              title: Text('No entities currently flagged for attention.'),
            ),
          )
        else
          ...attention.map((entity) {
            final name = (entity['name'] ?? '').toString();
            final status =
                (entity['attention_status'] ?? 'unknown').toString();
            final focus = (entity['current_focus'] ?? '').toString();
            return Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.priority_high),
                title: Text(name),
                subtitle: Text(
                  focus.isEmpty ? status : '$status · $focus',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openEntityDetail(context, name),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspect'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Entities'),
            Tab(text: 'Relationships'),
            Tab(text: 'Appointments'),
            Tab(text: 'Priorities'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildCountsStrip(context),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildEntitiesTab(),
                _buildRelationshipsTab(),
                _buildAppointmentsTab(),
                _buildPrioritiesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
