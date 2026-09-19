import 'package:flutter/material.dart';

import '../models/entity_type.dart';
import '../services/wisdom_service.dart';
import '../widgets/curiosity_panel.dart';
import '../widgets/entity_editor_sheet.dart';
import '../widgets/entity_type_chip.dart';

/// Thin, mostly read-only inspect surface over the live life graph.
///
/// Shows counts + browse tabs for entities, relationships, appointments
/// (dated action_items), and attention/priorities from existing signals.
/// Adds typed create/edit and a calm curiosity panel — not life-OS clutter.
class InspectDashboardPage extends StatefulWidget {
  const InspectDashboardPage({
    super.key,
    required this.entities,
    required this.relationships,
    required this.tasks,
    required this.wisdomService,
    this.embedded = false,
  });

  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> relationships;
  final List<Map<String, dynamic>> tasks;
  final WisdomService wisdomService;

  /// When true, render as a body widget (no Scaffold) for use as app home.
  final bool embedded;

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
      final type = EntityType.parse(entity['type']?.toString()).firestoreValue;
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, dynamic>> get _filteredEntities {
    if (_entityTypeFilter == 'all') return widget.entities;
    return widget.entities
        .where(
          (e) =>
              EntityType.parse(e['type']?.toString()).firestoreValue ==
              _entityTypeFilter,
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
      'type': 'other',
      'summary': '',
      'attention_status': 'unknown',
      'current_focus': '',
      'address': '',
      'located_in_entity_id': '',
    };
  }

  String _entityNameById(String id) {
    for (final e in widget.entities) {
      if ((e['id'] ?? '').toString() == id) {
        return (e['name'] ?? id).toString();
      }
    }
    return id;
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

  Future<void> _createEntity() async {
    await showEntityEditorSheet(
      context,
      allEntities: widget.entities,
    );
  }

  Future<void> _editEntity(Map<String, dynamic> entity) async {
    await showEntityEditorSheet(
      context,
      existing: entity,
      allEntities: widget.entities,
    );
  }

  void _openEntityDetail(BuildContext context, String label) {
    final entity = _entityForLabel(label);
    final linkedTasks = _linkedTasksFor(label);
    final edges = _edgesFor(label);
    final summary = (entity['summary'] ?? '').toString();
    final focus = (entity['current_focus'] ?? '').toString();
    final status = (entity['attention_status'] ?? 'unknown').toString();
    final type = EntityType.parse(entity['type']?.toString());
    final address = (entity['address'] ?? '').toString();
    final locatedIn = (entity['located_in_entity_id'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: type.softBackground,
                        foregroundColor: type.color,
                        child: Icon(type.icon),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entity['name'].toString(),
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      EntityTypeChip(type: type, compact: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      Chip(
                        label: Text(status),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(summary),
                  ],
                  if (focus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Focus: $focus'),
                  ],
                  if (type.isPlace && address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Address: $address'),
                  ],
                  if (type == EntityType.venue && locatedIn.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Located in: ${_entityNameById(locatedIn)}'),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Linked actions (${linkedTasks.length})',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleSmall
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
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleSmall
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
                              rel['summary'] ??
                              rel['description'] ??
                              'related')
                          .toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $from → $to ($relType)'),
                      );
                    }),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if ((entity['id'] ?? '').toString().isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _editEntity(entity);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _countChip(
    BuildContext context,
    String label,
    int count, {
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = accent?.withValues(alpha: 0.16) ??
        scheme.primaryContainer.withValues(alpha: 0.55);
    final fg = accent ?? scheme.onPrimaryContainer;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: bg,
      side: BorderSide(color: (accent ?? scheme.primary).withValues(alpha: 0.35)),
      label: Text(
        '$label: $count',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildCountsStrip(BuildContext context) {
    final typeCounts = _entityTypeCounts;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.hub,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  'Live graph',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createEntity,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Entity'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _countChip(
                  context,
                  'Entities',
                  widget.entities.length,
                  accent: const Color(0xFF5B6CFF),
                ),
                _countChip(
                  context,
                  'Relationships',
                  widget.relationships.length,
                  accent: const Color(0xFF7C4DFF),
                ),
                _countChip(
                  context,
                  'Open actions',
                  _openTasks.length,
                  accent: const Color(0xFF00897B),
                ),
                _countChip(
                  context,
                  'Appointments',
                  _appointments.length,
                  accent: const Color(0xFFE65100),
                ),
                _countChip(
                  context,
                  'Attention',
                  _attentionEntities.length,
                  accent: const Color(0xFFC62828),
                ),
              ],
            ),
            if (typeCounts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: typeCounts.entries.map((e) {
                  final t = EntityType.parse(e.key);
                  return Chip(
                    avatar: Icon(t.icon, size: 14, color: t.color),
                    label: Text(
                      '${t.label} ${e.value}',
                      style: TextStyle(
                        color: t.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: t.softBackground,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: t.color.withValues(alpha: 0.35)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntityTypeFilters() {
    final filterTypes = <String>[
      'all',
      ...EntityType.all.map((t) => t.firestoreValue),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: filterTypes.map((typeKey) {
          if (typeKey == 'all') {
            final selected = _entityTypeFilter == 'all';
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: const Text('All'),
                selected: selected,
                onSelected: (_) => setState(() => _entityTypeFilter = 'all'),
              ),
            );
          }
          final t = EntityType.parse(typeKey);
          final selected = _entityTypeFilter == typeKey;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: EntityTypeChip(
              type: t,
              selected: selected,
              compact: true,
              onSelected: (_) => setState(() => _entityTypeFilter = typeKey),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyEntities() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              widget.entities.isEmpty
                  ? 'Graph is empty — add an entity to begin.'
                  : 'No entities in this filter.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _createEntity,
              icon: const Icon(Icons.add),
              label: const Text('Add entity'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityCard(Map<String, dynamic> entity) {
    final name = (entity['name'] ?? '').toString();
    final type = EntityType.parse(entity['type']?.toString());
    final status = (entity['attention_status'] ?? 'unknown').toString();
    final summary = (entity['summary'] ?? '').toString();
    final address = (entity['address'] ?? '').toString();
    final locatedIn = (entity['located_in_entity_id'] ?? '').toString();
    final placeBits = <String>[];
    if (type.isPlace && address.isNotEmpty) {
      placeBits.add(address);
    }
    if (type == EntityType.venue && locatedIn.isNotEmpty) {
      placeBits.add('in ${_entityNameById(locatedIn)}');
    }
    final subtitleParts = <String>[
      status,
      if (summary.isNotEmpty) summary,
      ...placeBits,
    ];
    return Card(
      elevation: 0,
      color: type.softBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: type.color.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: type.color,
          foregroundColor: Colors.white,
          child: Icon(type.icon, size: 18),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitleParts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: EntityTypeChip(
          type: type,
          compact: true,
          showIcon: false,
        ),
        onTap: () => _openEntityDetail(context, name),
        onLongPress: () => _editEntity(entity),
      ),
    );
  }

  /// Home/Entities tab: one continuous scroll — counts, curiosity, filters,
  /// and the entity list share the same CustomScrollView so short viewports
  /// are not starved by permanently pinned chrome.
  Widget _buildEntitiesTab() {
    final entities = _filteredEntities;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildCountsStrip(context)),
        SliverToBoxAdapter(
          child: CuriosityPanel(
            entities: widget.entities,
            relationships: widget.relationships,
          ),
        ),
        SliverToBoxAdapter(child: _buildEntityTypeFilters()),
        if (entities.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyEntities(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) {
                    return const SizedBox(height: 6);
                  }
                  return _buildEntityCard(entities[index ~/ 2]);
                },
                childCount: entities.isEmpty ? 0 : entities.length * 2 - 1,
              ),
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
        final relType = (rel['type'] ??
                rel['summary'] ??
                rel['description'] ??
                'related')
            .toString();
        return Card(
          color: Theme.of(context)
              .colorScheme
              .tertiaryContainer
              .withValues(alpha: 0.45),
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.link,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            title: Text('$from → $to'),
            subtitle:
                Text(relType, maxLines: 2, overflow: TextOverflow.ellipsis),
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
          color: const Color(0xFFFFE0B2).withValues(alpha: 0.55),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.event, color: Color(0xFFE65100)),
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
          color: Theme.of(context)
              .colorScheme
              .errorContainer
              .withValues(alpha: 0.35),
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
            final type = EntityType.parse(entity['type']?.toString());
            return Card(
              color: type.softBackground,
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: type.color,
                  foregroundColor: Colors.white,
                  radius: 16,
                  child: Icon(type.icon, size: 16),
                ),
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

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      indicatorColor: Theme.of(context).colorScheme.secondary,
      labelColor: Theme.of(context).colorScheme.primary,
      tabs: const [
        Tab(text: 'Entities'),
        Tab(text: 'Relationships'),
        Tab(text: 'Appointments'),
        Tab(text: 'Priorities'),
      ],
    );
  }

  Widget _buildDashboardBody(BuildContext context) {
    // TabBarView fills remaining height; Entities tab scrolls as one page
    // (headers live inside that CustomScrollView, not pinned above it).
    return TabBarView(
      controller: _tabs,
      children: [
        _buildEntitiesTab(),
        _buildRelationshipsTab(),
        _buildAppointmentsTab(),
        _buildPrioritiesTab(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            elevation: 0,
            child: _buildTabBar(),
          ),
          Expanded(child: _buildDashboardBody(context)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspect'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: _buildTabBar(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createEntity,
        icon: const Icon(Icons.add),
        label: const Text('Entity'),
      ),
      body: _buildDashboardBody(context),
    );
  }
}
