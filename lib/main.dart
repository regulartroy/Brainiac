// ignore_for_file: unused_element, unused_field
// Life-OS capture/ask/wisdom UI was stripped from the product shell in the
// graph-shell-home change; helpers above stay temporarily for a later rip.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:convert';
import 'dart:async';
import 'js_bridge.dart' as js_bridge;

import 'services/brain_agent_service.dart';
import 'services/pruning_service.dart';
import 'services/wisdom_service.dart';
import 'app_version.dart';
import 'screens/inspect_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  setupEmulators();

  runApp(const SecondBrainApp());
}

void setupEmulators() {
  const useLocalFunctions = bool.fromEnvironment('USE_LOCAL_FUNCTIONS');
  if (kDebugMode || useLocalFunctions) {
    final host = kIsWeb ? Uri.base.host : '127.0.0.1';

    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  }
}

class SecondBrainApp extends StatefulWidget {
  const SecondBrainApp({super.key});

  @override
  State<SecondBrainApp> createState() => _SecondBrainAppState();
}

enum TaskFilter { all, open, done, review }

enum CaptureMode { task, person, detail }

class CuratedQuestion {
  const CuratedQuestion({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.entityId,
    required this.entityName,
    this.relatedEntityId,
    this.relatedEntityName,
  });

  final String id;
  final String kind;
  final String prompt;
  final String entityId;
  final String entityName;
  final String? relatedEntityId;
  final String? relatedEntityName;

  factory CuratedQuestion.fromMap(Map<String, dynamic> map) {
    return CuratedQuestion(
      id: map['id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'entity_detail',
      prompt: map['prompt']?.toString() ?? '',
      entityId: map['entityId']?.toString() ?? '',
      entityName: map['entityName']?.toString() ?? '',
      relatedEntityId: map['relatedEntityId']?.toString(),
      relatedEntityName: map['relatedEntityName']?.toString(),
    );
  }
}

class MasterCalendarPage extends StatefulWidget {
  const MasterCalendarPage({
    super.key,
    required this.tasks,
    required this.wisdomService,
  });

  final List<Map<String, dynamic>> tasks;
  final WisdomService wisdomService;

  @override
  State<MasterCalendarPage> createState() => _MasterCalendarPageState();
}

class _MasterCalendarPageState extends State<MasterCalendarPage> {
  String _clientFilter = '';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    final entries = widget.wisdomService.compileCalendar(
      tasks: widget.tasks,
      now: now,
    );

    final filteredEntries = entries.where((entry) {
      final matchesClient =
          _clientFilter.trim().isEmpty ||
          entry.client.toLowerCase().contains(_clientFilter.toLowerCase()) ||
          entry.title.toLowerCase().contains(_clientFilter.toLowerCase());
      final isWithinWindow =
          !entry.startsAt.isBefore(now) && !entry.startsAt.isAfter(horizon);
      return matchesClient && isWithinWindow;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Master calendar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by client or task',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _clientFilter = value),
            ),
            const SizedBox(height: 16),
            Text(
              'Next 30 days',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredEntries.isEmpty
                  ? const Center(
                      child: Text('No scheduled appointments in this window.'),
                    )
                  : ListView.builder(
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final endSuffix = entry.endsAt == null
                            ? ''
                            : '–${entry.endsAt!.hour.toString().padLeft(2, '0')}:${entry.endsAt!.minute.toString().padLeft(2, '0')}';
                        final dateLabel =
                            '${entry.startsAt.day}/${entry.startsAt.month} ${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}$endSuffix';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(entry.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Client: ${entry.client}'),
                                Text('Category: ${entry.category}'),
                                Text(entry.place.isEmpty ? 'Place: (not set)' : 'Place: ${entry.place}'),
                                Text('When: $dateLabel'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class GraphViewPage extends StatelessWidget {
  const GraphViewPage({
    super.key,
    required this.tasks,
    required this.entities,
    required this.relationships,
    required this.wisdomService,
  });

  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> relationships;
  final WisdomService wisdomService;

  Map<String, dynamic> _entityForLabel(String label) {
    final lower = label.toLowerCase();
    for (final entity in entities) {
      final name = entity['name']?.toString() ?? '';
      if (name.toLowerCase() == lower) {
        return entity;
      }
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
    return tasks.where((task) {
      final status = task['status']?.toString() ?? 'open';
      if (status == 'done' || status == 'archived') return false;
      final links = (task['linked_entities'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().toLowerCase());
      return links.contains(lower);
    }).toList();
  }

  void _openEntityDetail(BuildContext context, String label) {
    final entity = _entityForLabel(label);
    final linkedTasks = _linkedTasksFor(label);
    final summary = entity['summary']?.toString() ?? '';
    final focus = entity['current_focus']?.toString() ?? '';
    final status = entity['attention_status']?.toString() ?? 'unknown';
    final type = entity['type']?.toString() ?? 'entity';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                Text('$type'),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(summary),
                ],
                if (focus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Focus: $focus'),
                ],
                if (linkedTasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Linked actions',
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...linkedTasks.take(8).map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${task['description']}'),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const Text('No open linked actions.'),
                ],
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final graph = wisdomService.compileKnowledgeGraph(
      tasks: tasks,
      entities: entities,
      relationships: relationships,
    );
    final positions = <String, Offset>{};
    final center = const Offset(0.5, 0.5);

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge graph')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(graph.summary, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              'Tap a node to open entity detail.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final safeWidth = width.isFinite ? width : 500.0;
                  final safeHeight = height.isFinite ? height : 500.0;
                  for (int index = 0; index < graph.nodes.length; index++) {
                    final node = graph.nodes[index];
                    final angle =
                        (2 * 3.14159 * index) /
                        (graph.nodes.length == 1 ? 1 : graph.nodes.length);
                    final x = (center.dx + (cos(angle) * 0.26)) * safeWidth;
                    final y = (center.dy + (sin(angle) * 0.26)) * safeHeight;
                    positions[node.label] = Offset(
                      x.clamp(40.0, safeWidth - 80.0),
                      y.clamp(40.0, safeHeight - 80.0),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GraphPainter(
                              nodes: graph.nodes,
                              connections: graph.connections,
                              positions: positions,
                            ),
                          ),
                        ),
                        ...graph.nodes.asMap().entries.map((entry) {
                          final index = entry.key;
                          final node = entry.value;
                          final position =
                              positions[node.label] ??
                              Offset(safeWidth / 2, safeHeight / 2);
                          final color = Colors
                              .primaries[index % Colors.primaries.length]
                              .withOpacity(0.72);

                          return Positioned(
                            left: position.dx - 58,
                            top: position.dy - 22,
                            child: GestureDetector(
                              onTap: () =>
                                  _openEntityDetail(context, node.label),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  width: 116,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    node.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.nodes,
    required this.connections,
    required this.positions,
  });

  final List<GraphNode> nodes;
  final List<String> connections;
  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.deepPurple.withOpacity(0.35)
      ..strokeWidth = 2;

    for (final connection in connections) {
      final parts = connection.split(' ↔ ');
      if (parts.length != 2) continue;
      final start = positions[parts[0]];
      final end = positions[parts[1]];
      if (start == null || end == null) continue;
      canvas.drawLine(start, end, linePaint);
    }

    for (final node in nodes) {
      final point = positions[node.label];
      if (point == null) continue;
      final ring = Paint()
        ..color = Colors.deepPurple.withOpacity(0.15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, 34, ring);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AttentionPage extends StatefulWidget {
  const AttentionPage({super.key, required this.entities, required this.tasks});

  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> tasks;

  @override
  State<AttentionPage> createState() => _AttentionPageState();
}

class _AttentionPageState extends State<AttentionPage> {
  final Map<String, bool> _saving = {};

  Future<void> _addAction(Map<String, dynamic> entity) async {
    final controller = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Next action for ${entity['name']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Follow up by email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add action'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (action == null || action.isEmpty) return;
    final name = entity['name'].toString();
    setState(() => _saving[name] = true);
    try {
      await FirebaseFirestore.instance.collection('action_items').add({
        'description': action,
        'linked_entities': [name],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'active_attention',
      });
      await FirebaseFirestore.instance
          .collection('entities')
          .doc(entity['id'].toString())
          .set({
            'attention_status': 'active',
            'current_focus': action,
            'next_action': action,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _saving.remove(name));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Action added for $name.')));
    } catch (error) {
      debugPrint('Failed to add attention action: $error');
      if (!mounted) return;
      setState(() => _saving.remove(name));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add that action.')),
      );
    }
  }

  Future<void> _setDate(Map<String, dynamic> entity) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: DateTime.now(),
    );
    if (picked == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('entities')
          .doc(entity['id'].toString())
          .set({
            'next_date': picked.toIso8601String(),
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      final linkedTasks = await FirebaseFirestore.instance
          .collection('action_items')
          .where('linked_entities', arrayContains: entity['name'].toString())
          .get();
      final taskBatch = FirebaseFirestore.instance.batch();
      for (final task in linkedTasks.docs) {
        final status = task.data()['status']?.toString() ?? 'open';
        if (status != 'done' && status != 'archived') {
          taskBatch.update(task.reference, {
            'startAt': picked.toIso8601String(),
            'scheduledAt': picked.toIso8601String(),
            'dueDate': picked.toIso8601String(),
          });
        }
      }
      await taskBatch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Date saved for ${entity['name']}.')),
      );
    } catch (error) {
      debugPrint('Failed to save attention date: $error');
    }
  }

  String _taskKey(String description) => description
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  bool _isSatisfiedPersonAdd(Map<String, dynamic> task) {
    final description = (task['description'] ?? '').toString().toLowerCase();
    if (!RegExp(r'\b(add|create|save|remember)\b').hasMatch(description) ||
        !RegExp(r'\bas\s+a?\s*person\b').hasMatch(description)) {
      return false;
    }
    final links = (task['linked_entities'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((link) => link.toLowerCase());
    return links.any(
      (link) => widget.entities.any(
        (entity) => entity['name'].toString().toLowerCase() == link,
      ),
    );
  }

  String? _responsibleEntity(Map<String, dynamic> task) {
    final description = (task['description'] ?? '').toString().toLowerCase();
    final links = (task['linked_entities'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    for (final link in links) {
      final lowerLink = link.toLowerCase();
      if (RegExp(
        '\\b(with|for|from|to)\\s+${RegExp.escape(lowerLink)}\\b',
      ).hasMatch(description)) {
        return link;
      }
    }
    return links.length == 1 ? links.first : null;
  }

  List<Map<String, dynamic>> _attentionTasksFor(String name) {
    final seen = <String>{};
    return widget.tasks.where((task) {
      final status = task['status']?.toString() ?? 'open';
      if (status == 'done' ||
          status == 'archived' ||
          _isSatisfiedPersonAdd(task)) {
        return false;
      }
      final responsible = _responsibleEntity(task);
      if (responsible == null ||
          responsible.toLowerCase() != name.toLowerCase()) {
        return false;
      }
      final key = _taskKey((task['description'] ?? '').toString());
      return key.isNotEmpty && seen.add(key);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final attentionEntities = widget.entities.where((entity) {
      final status = entity['attention_status']?.toString() ?? 'unknown';
      final name = entity['name']?.toString() ?? '';
      return status == 'active' ||
          status == 'waiting' ||
          (name.isNotEmpty && _attentionTasksFor(name).isNotEmpty);
    }).toList();
    final quietCount = widget.entities.where((entity) {
      final status = entity['attention_status']?.toString() ?? 'unknown';
      return status == 'clear' || status == 'dormant';
    }).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Active attention')),
      body: attentionEntities.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      'No people or projects currently need attention.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$quietCount people or projects are clear or resting.',
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Who needs attention now',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Active work and waiting dependencies are shown here. Clear people stay out of the urgent view.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ...attentionEntities.map((entity) {
                  final name = entity['name'].toString();
                  final storedStatus =
                      entity['attention_status']?.toString() ?? 'unknown';
                  final attentionTasks = _attentionTasksFor(name);
                  final status =
                      attentionTasks.isNotEmpty &&
                          storedStatus != 'active' &&
                          storedStatus != 'waiting'
                      ? 'needs action'
                      : storedStatus;
                  final focus = entity['current_focus']?.toString() ?? '';
                  final linkedTasks = attentionTasks;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                status == 'waiting'
                                    ? Icons.hourglass_top
                                    : Icons.priority_high,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Chip(label: Text(status)),
                            ],
                          ),
                          if (focus.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(focus),
                          ],
                          if (linkedTasks.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Open actions',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            ...linkedTasks.map(
                              (task) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('• ${task['description']}'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _saving[name] == true
                                    ? null
                                    : () => _addAction(entity),
                                icon: const Icon(Icons.add_task),
                                label: const Text('Add action'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _setDate(entity),
                                icon: const Icon(Icons.event_outlined),
                                label: const Text('Set date'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _SecondBrainAppState extends State<SecondBrainApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final brainService = BrainAgentService();
  final PruningService _pruningService = PruningService();
  final WisdomService _wisdomService = WisdomService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _brainiacController = TextEditingController();

  bool _isListening = false;
  CaptureMode _captureMode = CaptureMode.task;
  bool _showInsights = true;
  TaskFilter _taskFilter = TaskFilter.all;
  String? _focusFilter;
  String _statusMessage = 'Ready — shared memory graph';
  bool _statusIsError = false;
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _insightHistory = const [];
  List<Map<String, dynamic>> _archivedTasks = const [];
  List<Map<String, dynamic>> _captureArchive = const [];
  Map<String, dynamic> _latestInsight = const {};
  int _retentionDays = 30;
  String _brainiacAnswer =
      'Ask me what matters most and I will summarise the memory graph.';
  List<String> _brainiacHighlights = const [];

  // Review panel state
  bool _reviewPanelOpen = false;
  bool _entityMergePanelOpen = false;
  bool _isSubmitting = false;
  List<ReviewItem> _pendingReviewItems = [];
  Map<String, String> _reviewMappings = {}; // reviewItem.id -> chosen label
  List<String> _entitySuggestions = [];
  Map<String, TextEditingController> _reviewControllers = {};
  Map<String, bool> _editingReview = {};
  List<Map<String, dynamic>> _entityGroups = [];
  List<Map<String, dynamic>> _entities = [];
  List<Map<String, dynamic>> _relationships = [];
  StreamSubscription? _actionItemsSub;
  StreamSubscription? _entitiesSub;
  StreamSubscription? _relationshipsSub;
  StreamSubscription? _insightsSub;
  StreamSubscription? _captureArchiveSub;
  StreamSubscription? _retentionSettingsSub;

  @override
  void initState() {
    super.initState();
    _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'notListening' && _isListening) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _statusIsError = true;
          _statusMessage = 'Microphone unavailable: ${error.errorMsg}';
        });
      },
    );
    // Expose a JS hook so tests or automation can inject tasks directly into
    // the Flutter in-memory task list. Call from the page with:
    // window.SECOND_BRAIN_PUSH(JSON.stringify({tasks:[{description:'...', linked_entities:[], status:'open'}]}))
    try {
      js_bridge.context['SECOND_BRAIN_PUSH'] = (dynamic json) {
        try {
          final payload = jsonDecode(json as String) as Map<String, dynamic>;
          final incoming = (payload['tasks'] as List<dynamic>?) ?? const [];
          setState(() {
            for (final item in incoming) {
              if (item is Map) {
                _tasks.insert(
                  0,
                  Map<String, dynamic>.from(item.cast<String, dynamic>()),
                );
              }
            }
          });

          // Keep a mirror on the window for easy inspection
          final dump = jsonEncode({
            'tasks': _tasks,
            'filter': _taskFilter.toString(),
          });
          js_bridge.context['SECOND_BRAIN_STATE'] = dump;
        } catch (e) {
          debugPrint('SECOND_BRAIN_PUSH failed: $e');
        }
      };
    } catch (e) {
      debugPrint('Failed to register SECOND_BRAIN_PUSH: $e');
    }

    // Live Firestore stream: keep UI in sync with persisted `action_items`.
    try {
      if (Firebase.apps.isNotEmpty) {
        _actionItemsSub = FirebaseFirestore.instance
            .collection('action_items')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .listen(
              (snapshot) {
                setState(() {
                  _tasks = snapshot.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final linked = data['linked_entities'];
                    List<String> links = [];
                    if (linked is List) {
                      links = linked.whereType<String>().toList();
                    }

                    return {
                      'id': doc.id,
                      'description': data['description']?.toString() ?? '',
                      'linked_entities': links,
                      'linked_entity_ids':
                          (data['linked_entity_ids'] as List<dynamic>? ??
                                  const [])
                              .map((item) => item.toString())
                              .toList(),
                      'status': data['status']?.toString() ?? 'open',
                      'category': data['category']?.toString() ?? '',
                      'client': data['client']?.toString() ?? '',
                      'place': data['place']?.toString() ?? '',
                      'startAt': data['startAt']?.toString() ?? '',
                      'endAt': data['endAt']?.toString() ?? '',
                      'scheduledAt': data['scheduledAt']?.toString() ?? '',
                      'dueDate': data['dueDate']?.toString() ?? '',
                    };
                  }).toList();

                  try {
                    js_bridge.context['SECOND_BRAIN_STATE'] = jsonEncode({
                      'tasks': _tasks,
                      'filter': _taskFilter.toString(),
                    });
                  } catch (_) {}
                });
              },
              onError: (Object error) {
                if (!mounted) return;
                setState(() {
                  _statusIsError = true;
                  _statusMessage =
                      'Could not read active tasks from Firebase: $error';
                });
              },
            );
      }
    } catch (e) {
      debugPrint('Failed to subscribe to action_items: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _entitiesSub = FirebaseFirestore.instance
            .collection('entities')
            .orderBy('name')
            .snapshots()
            .listen(
              (snapshot) {
                if (!mounted) return;
                setState(() {
                  _entities = snapshot.docs.map((doc) {
                    final data = doc.data();
                    return {
                      'id': doc.id,
                      'name': data['name']?.toString() ?? doc.id,
                      'type': data['type']?.toString() ?? 'other',
                      'summary': data['summary']?.toString() ?? '',
                      'attention_status':
                          data['attention_status']?.toString() ?? 'unknown',
                      'current_focus': data['current_focus']?.toString() ?? '',
                      'address': data['address']?.toString() ?? '',
                      'located_in_entity_id':
                          data['located_in_entity_id']?.toString() ?? '',
                    };
                  }).toList();
                });
              },
              onError: (Object error) {
                if (!mounted) return;
                setState(() {
                  _statusIsError = true;
                  _statusMessage =
                      'Could not read entities from Firebase: $error';
                });
              },
            );
      }
    } catch (e) {
      debugPrint('Failed to subscribe to entities: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _relationshipsSub = FirebaseFirestore.instance
            .collection('relationships')
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              setState(() {
                _relationships = snapshot.docs.map((doc) {
                  final data = doc.data();
                  return {
                    'id': doc.id,
                    'from_entity_id':
                        data['from_entity_id']?.toString() ?? '',
                    'to_entity_id': data['to_entity_id']?.toString() ?? '',
                    'from_entity': data['from_entity']?.toString() ?? '',
                    'to_entity': data['to_entity']?.toString() ?? '',
                    'type': data['type']?.toString() ??
                        data['description']?.toString() ??
                        'related',
                    'summary': data['summary']?.toString() ??
                        data['description']?.toString() ??
                        '',
                    'labels': data['labels'] ?? const [],
                  };
                }).toList();
              });
            });
      }
    } catch (e) {
      debugPrint('Failed to subscribe to relationships: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _insightsSub = FirebaseFirestore.instance
            .collection('insights')
            .orderBy('generatedAt', descending: true)
            .limit(5)
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              setState(() {
                _insightHistory = snapshot.docs.map((doc) {
                  final data = doc.data();
                  return {
                    'id': doc.id,
                    'summary': data['summary']?.toString() ?? '',
                    'connections': data['connections'] ?? const [],
                    'clusterAdvice': data['clusterAdvice'] ?? const [],
                    'generatedAt': data['generatedAt'],
                  };
                }).toList();

                if (snapshot.docs.isNotEmpty) {
                  final data = snapshot.docs.first.data();
                  _latestInsight = data;
                } else {
                  _latestInsight = const {};
                }
              });
            });
      }
    } catch (e) {
      debugPrint('Failed to subscribe to insights: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('completed_tasks')
            .orderBy('completedAt', descending: true)
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              setState(() {
                _archivedTasks = snapshot.docs.map((doc) {
                  final data = doc.data();
                  final linked = data['linked_entities'];
                  List<String> links = [];
                  if (linked is List) {
                    links = linked.whereType<String>().toList();
                  }

                  return {
                    'id': doc.id,
                    'description': data['description']?.toString() ?? '',
                    'linked_entities': links,
                    'status': data['status']?.toString() ?? 'done',
                    'completedAt': data['completedAt'],
                  };
                }).toList();
              });
            });
      }
    } catch (e) {
      debugPrint('Failed to subscribe to completed_tasks: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _captureArchiveSub = FirebaseFirestore.instance
            .collection('capture_archive')
            .orderBy('archivedAt', descending: true)
            .limit(5)
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              setState(() {
                _captureArchive = snapshot.docs.map((doc) {
                  final data = doc.data();
                  return {
                    'id': doc.id,
                    'content': data['content']?.toString() ?? '',
                    'rawPreview': data['rawPreview']?.toString() ?? '',
                    'archivedAt': data['archivedAt'],
                    'createdAt': data['createdAt'],
                  };
                }).toList();
              });
            });
      }
    } catch (e) {
      debugPrint('Failed to subscribe to capture_archive: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _retentionSettingsSub = FirebaseFirestore.instance
            .collection('system_settings')
            .doc('retention_policy')
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;
              final value = snapshot.data()?['retentionDays'];
              if (value is num && value > 0) {
                setState(() {
                  _retentionDays = value.toInt();
                });
              }
            });
      }
    } catch (e) {
      debugPrint('Failed to subscribe to retention settings: $e');
    }
  }

  @override
  void dispose() {
    _actionItemsSub?.cancel();
    _entitiesSub?.cancel();
    _relationshipsSub?.cancel();
    _insightsSub?.cancel();
    _captureArchiveSub?.cancel();
    _retentionSettingsSub?.cancel();
    _textController.dispose();
    _brainiacController.dispose();
    super.dispose();
  }

  void _listen() async {
    if (!_isListening) {
      // Start listening
      bool available = await _speech.initialize(
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _statusIsError = true;
            _statusMessage = 'Microphone unavailable: ${error.errorMsg}';
          });
        },
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            // Feed audio directly into the text box
            _textController.text = val.recognizedWords;
          }),
        );
      } else {
        setState(() {
          _statusIsError = true;
          _statusMessage =
              'Microphone permission was not granted. Use HTTPS and allow microphone access in Brave site settings.';
        });
      }
    } else {
      // Stop listening and send
      setState(() => _isListening = false);
      _speech.stop();
      _submitNote(_textController.text);
    }
  }

  void _askBrainiac() {
    final question = _brainiacController.text.trim();
    if (question.isEmpty) return;

    final answer = _wisdomService.answerQuestion(
      question: question,
      tasks: _tasks,
    );

    setState(() {
      _brainiacAnswer = answer.answer;
      _brainiacHighlights = answer.highlights;
    });
  }

  Future<void> _openReviewPanel(
    List<ReviewItem> items,
    String pendingNote,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('entities')
          .get();
      _entitySuggestions = snap.docs
          .map((d) => (d.data()['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      _entitySuggestions = const [];
    }

    setState(() {
      _pendingReviewItems = items;
      _reviewMappings.clear();
      for (final it in items) {
        _reviewMappings[it.id] = it.label;
      }
      _reviewPanelOpen = true;
      _textController.text = pendingNote;
    });
  }

  String _normalizeEntityKey(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _refreshEntityDedupePanel({String? status}) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('entities')
          .get();

      final records = snapshot.docs
          .map(
            (doc) => EntityRecord(
              id: doc.id,
              name: (doc.data()['name'] ?? '').toString(),
              type: (doc.data()['type'] ?? 'concept').toString(),
              summary: (doc.data()['summary'] ?? '').toString(),
            ),
          )
          .toList();

      final dedupedGroups = _pruningService.groupDuplicateEntities(records);
      final normalizedMap =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

      for (final doc in snapshot.docs) {
        final name = (doc.data()['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final key = _normalizeEntityKey(name);
        normalizedMap.putIfAbsent(key, () => []).add(doc);
      }

      final remaining = dedupedGroups.map((group) {
        final key = _normalizeEntityKey(group.canonicalName);
        final docs =
            normalizedMap[key] ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return {'key': key, 'docs': docs, 'names': group.names};
      }).toList();

      if (!mounted) return;
      setState(() {
        _entityGroups = remaining;
        _entityMergePanelOpen = true;
        _statusIsError = false;
        if (status != null) {
          _statusMessage = status;
        } else if (remaining.isEmpty) {
          _statusMessage = 'No duplicate entities found after prune.';
        } else {
          _statusMessage =
              'Found ${remaining.length} duplicate group(s) still needing a merge.';
        }
      });
    } catch (e) {
      debugPrint('Failed to refresh entity dedupe panel: $e');
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = status ?? 'Could not refresh duplicate entity groups.';
      });
    }
  }

  Future<void> _loadDuplicateEntities() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'pruneDuplicateEntities',
      );
      final callResult = await callable.call(<String, dynamic>{});
      final mergeData =
          (callResult.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final mergedGroups = (mergeData['mergedGroups'] as num?)?.toInt() ?? 0;
      final entitiesDeleted =
          (mergeData['entitiesDeleted'] as num?)?.toInt() ?? 0;
      final actionItemsUpdated =
          (mergeData['actionItemsUpdated'] as num?)?.toInt() ?? 0;
      final relationshipsUpdated =
          (mergeData['relationshipsUpdated'] as num?)?.toInt() ?? 0;
      final relationshipsRemoved =
          (mergeData['relationshipsRemoved'] as num?)?.toInt() ?? 0;
      final relationshipsDeduped =
          (mergeData['relationshipsDeduped'] as num?)?.toInt() ?? 0;

      final snapshot = await FirebaseFirestore.instance
          .collection('entities')
          .get();

      final records = snapshot.docs
          .map(
            (doc) => EntityRecord(
              id: doc.id,
              name: (doc.data()['name'] ?? '').toString(),
              type: (doc.data()['type'] ?? 'concept').toString(),
              summary: (doc.data()['summary'] ?? '').toString(),
            ),
          )
          .toList();

      final dedupedGroups = _pruningService.groupDuplicateEntities(records);
      final normalizedMap =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

      for (final doc in snapshot.docs) {
        final name = (doc.data()['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final key = _normalizeEntityKey(name);
        normalizedMap.putIfAbsent(key, () => []).add(doc);
      }

      final remaining = dedupedGroups.map((group) {
        final key = _normalizeEntityKey(group.canonicalName);
        final docs =
            normalizedMap[key] ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return {'key': key, 'docs': docs, 'names': group.names};
      }).toList();

      final summaryParts = <String>[];
      if (mergedGroups > 0) {
        summaryParts.add(
          'Merged $mergedGroups group${mergedGroups == 1 ? '' : 's'} '
          '(deleted $entitiesDeleted)',
        );
      }
      if (actionItemsUpdated > 0) {
        summaryParts.add('rewrote $actionItemsUpdated action item(s)');
      }
      if (relationshipsUpdated + relationshipsRemoved + relationshipsDeduped >
          0) {
        summaryParts.add(
          'relationships u/r/d '
          '$relationshipsUpdated/$relationshipsRemoved/$relationshipsDeduped',
        );
      }

      final status = remaining.isEmpty
          ? (summaryParts.isEmpty
                ? 'No duplicate entities found after prune.'
                : '${summaryParts.join('; ')}. Graph is clean.')
          : (summaryParts.isEmpty
                ? 'Found ${remaining.length} duplicate group(s) still needing a merge.'
                : '${summaryParts.join('; ')}. ${remaining.length} group(s) still visible.');

      setState(() {
        _entityGroups = remaining;
        _entityMergePanelOpen = true;
        _statusIsError = false;
        _statusMessage = status;
      });
    } catch (e) {
      debugPrint('Failed to load duplicate entities: $e');
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not load duplicate entity groups.';
      });
    }
  }

  Future<void> _showDailyQuestions() async {
    if (mounted) {
      setState(() {
        _statusIsError = false;
        _statusMessage = 'Loading daily curation prompts...';
      });
    }
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateDailyQuestions',
      );
      final result = await callable.call(<String, dynamic>{});
      final data = result.data as Map<String, dynamic>? ?? const {};
      final questions = (data['questions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => CuratedQuestion.fromMap(Map<String, dynamic>.from(item)),
          )
          .where((question) => question.prompt.isNotEmpty)
          .toList();

      if (questions.isEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('entities')
            .get();

        final entities = snapshot.docs
            .map(
              (doc) => EntityRecord(
                name: (doc.data()['name'] ?? '').toString(),
                type: (doc.data()['type'] ?? 'concept').toString(),
                summary: (doc.data()['summary'] ?? '').toString(),
              ),
            )
            .toList();

        final fallbackQuestions = _pruningService.buildDailyQuestions(entities);
        if (fallbackQuestions.isEmpty) {
          setState(() {
            _statusMessage =
                'Add more entities to generate daily curation prompts.';
          });
          await _showQuestionDialog(const [
            CuratedQuestion(
              id: 'not-enough-entities',
              kind: 'entity_detail',
              prompt:
                  'There are not enough connected entities yet to generate a prompt.',
              entityId: '',
              entityName: '',
            ),
          ]);
          return;
        }

        await _showQuestionDialog(
          fallbackQuestions
              .map(
                (question) => CuratedQuestion(
                  id: 'fallback-${question.hashCode}',
                  kind: 'entity_detail',
                  prompt: question,
                  entityId: '',
                  entityName: '',
                ),
              )
              .toList(),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _statusMessage = 'Daily curation prompts ready.');
      await _showQuestionDialog(questions);
    } catch (e) {
      debugPrint('Failed to generate daily questions: $e');
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('entities')
            .get();
        final entities = snapshot.docs
            .map(
              (doc) => EntityRecord(
                name: (doc.data()['name'] ?? '').toString(),
                type: (doc.data()['type'] ?? 'concept').toString(),
                summary: (doc.data()['summary'] ?? '').toString(),
              ),
            )
            .toList();
        final fallbackQuestions = _pruningService.buildDailyQuestions(entities);
        if (fallbackQuestions.isNotEmpty) {
          await _showQuestionDialog(
            fallbackQuestions
                .map(
                  (question) => CuratedQuestion(
                    id: 'fallback-${question.hashCode}',
                    kind: 'entity_detail',
                    prompt: question,
                    entityId: '',
                    entityName: '',
                  ),
                )
                .toList(),
          );
          return;
        }
      } catch (_) {}

      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not generate the daily curation prompts.';
      });
      await _showQuestionDialog(const [
        CuratedQuestion(
          id: 'unavailable',
          kind: 'entity_detail',
          prompt:
              'Daily curation is temporarily unavailable. Try again after adding another person, place, or project.',
          entityId: '',
          entityName: '',
        ),
      ]);
    }
  }

  Future<void> _openMemoryPanel() async {
    final navigatorContext = _navigatorKey.currentContext;
    if (!mounted || navigatorContext == null) return;
    await showModalBottomSheet<void>(
      context: navigatorContext,
      isScrollControlled: true,
      builder: (context) {
        final openTasks = _tasks
            .where((task) => (task['status']?.toString() ?? 'open') == 'open')
            .length;
        final entities = _entities;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Memory',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('${_insightHistory.length} saved wisdom snapshots'),
                Text('$openTasks open tasks'),
                Text('${entities.length} people, places, and ideas in memory'),
                const SizedBox(height: 12),
                Text(
                  _latestInsight['summary']?.toString() ??
                      'No wisdom snapshot has been generated yet.',
                ),
                if (entities.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Recent entities',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...entities.take(8).map((entity) {
                    final type = (entity['type'] ?? '').toString().trim();
                    final status =
                        (entity['attention_status'] ?? '').toString().trim();
                    final focus =
                        (entity['current_focus'] ?? '').toString().trim();
                    final subtitleParts = <String>[
                      if (type.isNotEmpty) type,
                      if (status.isNotEmpty &&
                          status.toLowerCase() != 'unknown')
                        status,
                      if (focus.isNotEmpty) focus,
                    ];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        entity['type'] == 'person'
                            ? Icons.person_outline
                            : Icons.hub_outlined,
                      ),
                      title: Text(entity['name'].toString()),
                      subtitle: subtitleParts.isEmpty
                          ? null
                          : Text(subtitleParts.join(' • ')),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _refreshWisdomSnapshot();
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Refresh memory'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<String>?> _confirmAnswerEntities(List<ReviewItem> items) async {
    final navigatorContext = _navigatorKey.currentContext;
    if (!mounted || navigatorContext == null) return null;
    final selected = <String>{for (final item in items) item.id};
    return showDialog<List<String>>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Check the answer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Which people or organisations should this answer link to?',
              ),
              ...items.map(
                (item) => CheckboxListTile(
                  value: selected.contains(item.id),
                  title: Text(item.label),
                  subtitle: Text(item.type),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                items
                    .where((item) => selected.contains(item.id))
                    .map((item) => item.label)
                    .toList(),
              ),
              child: const Text('Use selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _answerCuratedQuestion(
    CuratedQuestion question,
    String answer,
  ) async {
    final cleanAnswer = answer.trim();
    if (cleanAnswer.isEmpty) return false;
    List<String> confirmedEntities = const [];
    try {
      final isAmbiguous =
          question.kind != 'entity_date' &&
          RegExp(
            r'\b(works for|reports to|client|connected to|related to|from|with)\b',
            caseSensitive: false,
          ).hasMatch(cleanAnswer);
      if (isAmbiguous) {
        final review = await brainService.extractTasksForReview(cleanAnswer);
        if (review.reviewItems.isNotEmpty) {
          confirmedEntities =
              await _confirmAnswerEntities(review.reviewItems) ?? const [];
          if (confirmedEntities.isEmpty) return false;
        }
      }
      if (question.kind == 'relationship' && question.relatedEntityId != null) {
        await FirebaseFirestore.instance.collection('relationships').add({
          'from_entity_id': question.entityId,
          'from_entity': question.entityName,
          'to_entity_id': question.relatedEntityId,
          'to_entity': question.relatedEntityName,
          'description': cleanAnswer,
          'confirmed_entities': confirmedEntities,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (question.entityId.isNotEmpty) {
        final ref = FirebaseFirestore.instance
            .collection('entities')
            .doc(question.entityId);
        final lowerAnswer = cleanAnswer.toLowerCase();
        final attentionStatus = question.kind == 'entity_status'
            ? lowerAnswer.contains('nothing') ||
                      lowerAnswer.contains('no action') ||
                      lowerAnswer.contains('not currently') ||
                      lowerAnswer.contains('clear for now') ||
                      lowerAnswer.contains('nothing outstanding')
                  ? 'clear'
                  : lowerAnswer.contains('waiting') ||
                        lowerAnswer.contains('awaiting')
                  ? 'waiting'
                  : lowerAnswer.contains('dormant') ||
                        lowerAnswer.contains('inactive')
                  ? 'dormant'
                  : 'active'
            : null;
        await ref.set({
          'summary': cleanAnswer,
          'confirmed_entities': confirmedEntities,
          if (attentionStatus != null) 'attention_status': attentionStatus,
          if (question.kind == 'entity_status') 'current_focus': cleanAnswer,
          if (question.kind == 'entity_date') 'next_date': cleanAnswer,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (!mounted) return true;
      setState(() => _statusMessage = 'Curation answer saved to memory.');
      return true;
    } catch (e) {
      debugPrint('Failed to save curation answer: $e');
      if (!mounted) return false;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not save that curation answer.';
      });
      return false;
    }
  }

  Future<List<CuratedQuestion>> _fetchCuratedQuestions({
    List<String> excludeIds = const [],
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'generateDailyQuestions',
    );
    final result = await callable.call(<String, dynamic>{
      'exclude_ids': excludeIds,
    });
    final data = result.data as Map<String, dynamic>? ?? const {};
    return (data['questions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => CuratedQuestion.fromMap(Map<String, dynamic>.from(item)))
        .where((question) => question.prompt.isNotEmpty)
        .toList();
  }

  CuratedQuestion _localReplacementQuestion(Set<String> excludedIds) {
    for (final entity in _entities) {
      final name = entity['name'].toString();
      final normalized = _normalizeEntityKey(name);
      final id = 'local-detail-$normalized';
      if (excludedIds.contains(id)) continue;
      return CuratedQuestion(
        id: id,
        kind: 'entity_detail',
        prompt: 'What useful context should I know about $name?',
        entityId: normalized.replaceAll(' ', '_'),
        entityName: name,
      );
    }
    return const CuratedQuestion(
      id: 'local-next-capture',
      kind: 'entity_detail',
      prompt: 'What important person, date, or connection should I add next?',
      entityId: '',
      entityName: '',
    );
  }

  Future<void> _showQuestionDialog(List<CuratedQuestion> questions) async {
    final navigatorContext = _navigatorKey.currentContext;
    if (!mounted || navigatorContext == null) return;
    await showDialog<void>(
      context: navigatorContext,
      builder: (context) {
        final controllers = <String, TextEditingController>{};
        final savingIds = <String>{};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Daily curation prompts'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: questions.length,
                itemBuilder: (context, index) {
                  final question = questions[index];
                  final controller = controllers.putIfAbsent(
                    question.id,
                    TextEditingController.new,
                  );
                  Future<void> saveAnswer() async {
                    if (controller.text.trim().isEmpty) {
                      setState(() {
                        _statusIsError = true;
                        _statusMessage = 'Write an answer before saving.';
                      });
                      return;
                    }
                    setDialogState(() => savingIds.add(question.id));
                    try {
                      final saved = await _answerCuratedQuestion(
                        question,
                        controller.text,
                      );
                      if (!saved || !context.mounted) return;
                      if (mounted) {
                        setState(() {
                          _statusIsError = false;
                          _statusMessage =
                              'Saved. Finding the next knowledge gap...';
                        });
                      }
                      final existingIds = questions
                          .map((item) => item.id)
                          .toSet();
                      List<CuratedQuestion> replacement;
                      try {
                        replacement = await _fetchCuratedQuestions(
                          excludeIds: existingIds.toList(),
                        ).timeout(const Duration(seconds: 5));
                      } on TimeoutException {
                        replacement = const [];
                      }
                      final next = replacement.firstWhere(
                        (item) => !existingIds.contains(item.id),
                        orElse: () => _localReplacementQuestion(existingIds),
                      );
                      setDialogState(() {
                        savingIds.remove(question.id);
                        final questionIndex = questions.indexOf(question);
                        if (questionIndex != -1 && next.id != question.id) {
                          questions[questionIndex] = next;
                        }
                        controller.clear();
                      });
                    } catch (e) {
                      debugPrint('Failed to replace curation question: $e');
                      setDialogState(() => savingIds.remove(question.id));
                      if (!mounted || !context.mounted) return;
                      setState(() {
                        _statusIsError = true;
                        _statusMessage =
                            'Answer saved, but the next prompt could not load. Try the curation button again.';
                      });
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(question.prompt),
                        const SizedBox(height: 6),
                        TextField(
                          controller: controller,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Add the missing context...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => saveAnswer(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: savingIds.contains(question.id)
                                ? null
                                : saveAnswer,
                            icon: savingIds.contains(question.id)
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              savingIds.contains(question.id)
                                  ? 'Saving...'
                                  : 'Save answer',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _refreshWisdomSnapshot() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateWisdomSnapshotCallable',
      );
      final result = await callable.call(<String, dynamic>{});
      final data = result.data as Map<String, dynamic>? ?? const {};
      if (!mounted) return;

      setState(() {
        _latestInsight = {
          'summary': data['summary'] ?? '',
          'connections': data['connections'] ?? const [],
          'clusterAdvice': data['clusterAdvice'] ?? const [],
          'generatedAt': DateTime.now().toIso8601String(),
        };
        _statusMessage = 'Wisdom snapshot refreshed.';
      });
    } catch (e) {
      debugPrint('Failed to refresh wisdom snapshot: $e');
    }
  }

  Future<void> _mergeEntityGroup(Map<String, dynamic> group) async {
    final docs =
        group['docs'] as List<QueryDocumentSnapshot<Map<String, dynamic>>>? ??
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (docs.length < 2) return;

    // Prefer the cloud merge path (rewrites refs + relationship hygiene).
    // Fall back to a local merge that also rewrites relationships if callable fails.
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'pruneDuplicateEntities',
      );
      final callResult = await callable.call(<String, dynamic>{});
      final mergeData =
          (callResult.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final mergedGroups = (mergeData['mergedGroups'] as num?)?.toInt() ?? 0;
      final actionItemsUpdated =
          (mergeData['actionItemsUpdated'] as num?)?.toInt() ?? 0;
      final relationshipsUpdated =
          (mergeData['relationshipsUpdated'] as num?)?.toInt() ?? 0;
      final relationshipsRemoved =
          (mergeData['relationshipsRemoved'] as num?)?.toInt() ?? 0;
      final relationshipsDeduped =
          (mergeData['relationshipsDeduped'] as num?)?.toInt() ?? 0;

      await _refreshWisdomSnapshot();
      await _refreshEntityDedupePanel(
        status:
            'Cloud merge: $mergedGroups group(s), '
            '$actionItemsUpdated action item(s) rewritten, '
            'relationships u/r/d '
            '$relationshipsUpdated/$relationshipsRemoved/$relationshipsDeduped.',
      );
      return;
    } catch (e) {
      debugPrint('Cloud merge failed; falling back to local merge: $e');
    }

    final canonicalDoc = docs.first;
    final canonicalData = canonicalDoc.data();
    final names = docs
        .map((doc) => (doc.data()['name'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final canonicalName = names.first;
    final canonicalType = (canonicalData['type'] ?? 'concept').toString();
    final mergedSummary = docs
        .map((doc) => (doc.data()['summary'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .join(' • ');
    final aliasIds = docs.map((doc) => doc.id).toSet();
    for (final name in names) {
      final derived = PruningService.entityIdForName(name);
      if (derived.isNotEmpty) aliasIds.add(derived);
    }

    final canonicalRef = FirebaseFirestore.instance
        .collection('entities')
        .doc(canonicalDoc.id);

    final batch = FirebaseFirestore.instance.batch();
    batch.set(canonicalRef, {
      'name': canonicalName,
      'type': canonicalType,
      'summary': mergedSummary.isNotEmpty
          ? mergedSummary
          : canonicalData['summary'] ?? '',
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final nameByKey = <String, String>{
      for (final name in names) _normalizeEntityKey(name): canonicalName,
    };
    final idByAlias = <String, String>{
      for (final id in aliasIds) id: canonicalDoc.id,
    };

    final taskSnapshot = await FirebaseFirestore.instance
        .collection('action_items')
        .get();
    var actionItemsUpdated = 0;
    for (final taskDoc in taskSnapshot.docs) {
      final taskData = taskDoc.data();
      final linked = (taskData['linked_entities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      final linkedIds =
          (taskData['linked_entity_ids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      final rewritten = _pruningService.rewriteLinkedEntities(
        linkedEntities: linked,
        linkedEntityIds: linkedIds,
        aliasNames: names.toSet(),
        aliasIds: aliasIds,
        canonicalName: canonicalName,
        canonicalId: canonicalDoc.id,
      );
      if (rewritten.changed) {
        actionItemsUpdated += 1;
        batch.update(taskDoc.reference, {
          'linked_entities': rewritten.linkedEntities,
          'linked_entity_ids': rewritten.linkedEntityIds,
        });
      }
    }

    final relationshipSnapshot = await FirebaseFirestore.instance
        .collection('relationships')
        .get();
    var relationshipsUpdated = 0;
    var relationshipsRemoved = 0;
    final seenEdgeKeys = <String>{};
    for (final relDoc in relationshipSnapshot.docs) {
      final data = relDoc.data();
      final rewritten = _pruningService.rewriteRelationship(
        fromEntity: (data['from_entity'] ?? '').toString(),
        toEntity: (data['to_entity'] ?? '').toString(),
        fromEntityId: (data['from_entity_id'] ?? '').toString(),
        toEntityId: (data['to_entity_id'] ?? '').toString(),
        type: (data['type'] ?? 'related').toString(),
        canonicalNameByKey: nameByKey,
        canonicalIdByAlias: idByAlias,
      );
      if (rewritten.drop || !seenEdgeKeys.add(rewritten.edgeKey)) {
        relationshipsRemoved += 1;
        batch.delete(relDoc.reference);
        continue;
      }
      if (rewritten.changed) {
        relationshipsUpdated += 1;
        batch.update(relDoc.reference, {
          'from_entity': rewritten.fromEntity,
          'to_entity': rewritten.toEntity,
          'from_entity_id': rewritten.fromEntityId,
          'to_entity_id': rewritten.toEntityId,
          'type': rewritten.type,
          'last_updated': FieldValue.serverTimestamp(),
        });
      }
    }

    for (final extraDoc in docs.skip(1)) {
      batch.delete(extraDoc.reference);
    }

    await batch.commit();
    await _refreshWisdomSnapshot();

    setState(() {
      _entityGroups = _entityGroups
          .where((entry) => entry['key'] != group['key'])
          .toList();
      _statusIsError = false;
      _statusMessage =
          'Merged ${docs.length} entities locally; '
          'rewrote $actionItemsUpdated action item(s); '
          'relationships updated/removed '
          '$relationshipsUpdated/$relationshipsRemoved.';
    });
  }

  Future<void> _submitWithConfirmedEntities() async {
    if (_isSubmitting) return;

    final selected = _pendingReviewItems
        .map(
          (it) => ReviewItem(
            id: it.id,
            label: _reviewMappings[it.id] ?? it.label,
            type: it.type,
          ),
        )
        .toList();

    _isSubmitting = true;

    try {
      final entityBatch = FirebaseFirestore.instance.batch();
      for (final item in selected) {
        final entityId = _normalizeEntityKey(item.label).replaceAll(' ', '_');
        final entityRef = FirebaseFirestore.instance
            .collection('entities')
            .doc(entityId);
        entityBatch.set(entityRef, {
          'name': item.label,
          'type': item.type.toLowerCase(),
          'summary': 'Confirmed from the user during entity review.',
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await entityBatch.commit();

      final extractedTasks = await brainService.extractTasksFromNote(
        _textController.text.trim(),
        selectedReviewItems: selected,
      );

      if (extractedTasks.isNotEmpty) {
        setState(() {
          for (final task in extractedTasks) {
            _tasks.insert(0, {
              'description': task,
              'linked_entities': const <String>[],
              'status': 'open',
            });
          }
          _statusMessage =
              'Saved ${selected.length} confirmed entit${selected.length == 1 ? 'y' : 'ies'} and extracted ${extractedTasks.length} task(s).';
        });
      } else {
        setState(() {
          _statusMessage =
              'Saved ${selected.length} confirmed entit${selected.length == 1 ? 'y' : 'ies'}. No task was found.';
        });
      }
    } catch (e) {
      debugPrint('Extraction Failed after review: $e');
      setState(() {
        _statusIsError = true;
        _statusMessage =
            'Extraction failed — check the local emulator connection.';
      });
    } finally {
      setState(() {
        _isSubmitting = false;
        _reviewPanelOpen = false;
        _pendingReviewItems = const [];
        _reviewMappings.clear();
      });
    }
  }

  Future<bool> _maybeCompleteTaskFromTranscript(String text) async {
    final note = text.trim();
    if (note.isEmpty) return false;

    final lower = note.toLowerCase();
    final completionKeywords = <String>{
      'done',
      'finished',
      'completed',
      'complete',
      'checked off',
      'resolved',
      'cleared',
      'dismissed',
      'remove',
      'deleted',
    };

    final isCompletion = completionKeywords.any(lower.contains);
    if (!isCompletion) return false;

    final candidateTasks = _tasks.where((task) {
      final description = (task['description'] ?? '').toString();
      if (description.trim().isEmpty) return false;
      final taskLower = description.toLowerCase();
      return lower.contains(taskLower) ||
          taskLower.contains(lower) ||
          taskLower
              .split(RegExp(r'\s+'))
              .where((part) => part.length > 3)
              .any((part) => lower.contains(part));
    }).toList();

    if (candidateTasks.isEmpty) return false;

    final task = candidateTasks.first;
    final description = (task['description'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm completion'),
        content: Text(
          'Mark “$description” as complete and archive it from the active list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive task'),
          ),
        ],
      ),
    );

    if (confirmed != true) return true;

    await _archiveTask(task);
    return true;
  }

  Future<bool> _maybeUpdateTaskFromTranscript(String text) async {
    final lower = text.toLowerCase();
    if (!lower.contains('follow up') &&
        !lower.contains('also') &&
        !lower.contains('too')) {
      return false;
    }

    final candidateTasks = _tasks.where((task) {
      final status = task['status']?.toString() ?? 'open';
      return status != 'done' && status != 'archived';
    }).toList();
    if (candidateTasks.isEmpty) return false;

    final review = await brainService.extractTasksForReview(text);
    if (review.reviewItems.isEmpty) return false;
    final confirmed = await _confirmAnswerEntities(review.reviewItems);
    if (confirmed == null || confirmed.isEmpty) return true;

    final mentionedNames = review.reviewItems
        .where((item) => confirmed.contains(item.label))
        .map((item) => item.label)
        .toList();
    final entityBatch = FirebaseFirestore.instance.batch();
    for (final item in review.reviewItems.where(
      (item) => confirmed.contains(item.label),
    )) {
      final entityId = _normalizeEntityKey(item.label).replaceAll(' ', '_');
      entityBatch.set(
        FirebaseFirestore.instance.collection('entities').doc(entityId),
        {
          'name': item.label,
          'type': item.type.toLowerCase(),
          'summary': 'Confirmed from a task follow-up.',
          'last_updated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await entityBatch.commit();
    final matchingTask = candidateTasks.firstWhere(
      (task) => (task['description'] ?? '').toString().toLowerCase().contains(
        'follow up',
      ),
      orElse: () => candidateTasks.first,
    );
    final taskId = matchingTask['id']?.toString();
    if (taskId == null || taskId.isEmpty) return true;

    final existingLinks =
        (matchingTask['linked_entities'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    final links = {...existingLinks, ...mentionedNames}.toList();
    await FirebaseFirestore.instance
        .collection('action_items')
        .doc(taskId)
        .update({
          'linked_entities': links,
          'last_updated': FieldValue.serverTimestamp(),
          'source_update': text,
        });
    if (!mounted) return true;
    setState(() {
      _statusIsError = false;
      _statusMessage =
          'Linked ${mentionedNames.join(', ')} to the existing task.';
    });
    return true;
  }

  Future<void> _updateRetentionDays(int value) async {
    final safeValue = value.clamp(1, 365);
    try {
      await FirebaseFirestore.instance
          .collection('system_settings')
          .doc('retention_policy')
          .set({
            'retentionDays': safeValue,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _retentionDays = safeValue;
      });
    } catch (e) {
      debugPrint('Failed to update retention policy: $e');
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not update retention policy.';
      });
    }
  }

  Future<void> _runRetentionSweep() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'runRetentionSweep',
      );
      final result = await callable.call(<String, dynamic>{
        'retentionDays': _retentionDays,
      });
      final archived = (result.data['archived'] as num?)?.toInt() ?? 0;
      setState(() {
        _statusMessage = 'Retention sweep archived $archived capture(s).';
        _statusIsError = false;
      });
    } catch (e) {
      debugPrint('Failed to run retention sweep: $e');
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not run retention sweep.';
      });
    }
  }

  bool _matchesFocusFilter(Map<String, dynamic> task) {
    if (_focusFilter == null || _focusFilter!.trim().isEmpty) {
      return true;
    }

    final focus = _focusFilter!.trim().toLowerCase();
    final description = (task['description'] ?? '').toString().toLowerCase();
    final linkedEntities =
        (task['linked_entities'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .map((entity) => entity.toLowerCase())
            .toList();

    return description.contains(focus) ||
        linkedEntities.any(
          (entity) => entity.contains(focus) || focus.contains(entity),
        );
  }

  Future<void> _submitNote(String text) async {
    final note = text.trim();
    if (note.isEmpty || _isSubmitting) return;

    final personIntent = RegExp(
      r'\b(?:add|create|save|remember)\b.+\bas\s+a?\s*person\b',
      caseSensitive: false,
    ).hasMatch(note);

    if (_captureMode == CaptureMode.person || personIntent) {
      await _submitPerson(note);
      return;
    }
    if (_captureMode == CaptureMode.detail) {
      await _submitDetail(note);
      return;
    }

    if (await _maybeUpdateTaskFromTranscript(note)) {
      _textController.clear();
      return;
    }

    if (await _maybeCompleteTaskFromTranscript(note)) {
      _textController.clear();
      return;
    }

    _isSubmitting = true;
    debugPrint('Checking note with review flow: $note');
    _textController.clear();
    setState(() {
      _statusIsError = false;
      _statusMessage = 'Processing note...';
    });

    try {
      final reviewResult = await brainService.extractTasksForReview(note);
      List<ReviewItem> selectedReviewItems = const [];

      final shouldReviewEntities =
          reviewResult.reviewItems.isNotEmpty &&
          (reviewResult.needsContext ||
              reviewResult.reviewItems.length > 1 ||
              reviewResult.reviewItems.any(
                (item) => const {
                  'person',
                  'venue',
                  'organization',
                  'project',
                  'equipment',
                  'location',
                }.contains(item.type.toLowerCase()),
              ));

      if (shouldReviewEntities) {
        setState(() {
          _statusMessage = 'Reviewing entity matches...';
        });

        await _openReviewPanel(reviewResult.reviewItems, note);
        return;
      }

      if (reviewResult.needsContext) {
        setState(() {
          _statusMessage =
              'This note needs a clearer entity reference before it can be processed.';
        });
        return;
      }

      final extractedTasks = await brainService.extractTasksFromNote(
        note,
        selectedReviewItems: selectedReviewItems,
      );

      if (extractedTasks.isNotEmpty) {
        setState(() {
          for (final task in extractedTasks) {
            _tasks.insert(0, {
              'description': task,
              'linked_entities': const <String>[],
              'status': 'open',
            });
          }
          _statusMessage = 'Extracted ${extractedTasks.length} task(s).';
        });
        await _refreshWisdomSnapshot();
      } else {
        setState(() {
          _statusMessage = 'No tasks found in this note.';
        });
      }
    } catch (e) {
      debugPrint('Extraction Failed: $e');
      setState(() {
        _statusIsError = true;
        _statusMessage =
            'Extraction failed — check the local emulator connection.';
      });
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _submitPerson(String text) async {
    final cleaned = text
        .replaceFirst(
          RegExp(r'^\s*(add|create|remember|save)\s+', caseSensitive: false),
          '',
        )
        .trim();
    final personMarker = RegExp(
      r'\s+as\s+a?\s*person\b',
      caseSensitive: false,
    ).firstMatch(cleaned);
    final name =
        (personMarker == null
                ? cleaned
                : cleaned.substring(0, personMarker.start))
            .trim();
    final trailingDetail = personMarker == null
        ? ''
        : cleaned.substring(personMarker.end).trim();
    if (name.isEmpty) return;

    try {
      final id = _normalizeEntityKey(name).replaceAll(' ', '_');
      await FirebaseFirestore.instance.collection('entities').doc(id).set({
        'name': name,
        'type': 'person',
        'summary': trailingDetail.isEmpty
            ? 'Added directly as a person.'
            : trailingDetail,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _textController.clear();
      if (!mounted) return;
      setState(() {
        _statusIsError = false;
        _statusMessage = '$name added as a person. No task was created.';
      });
      await _refreshWisdomSnapshot();
    } catch (e) {
      debugPrint('Failed to add person: $e');
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not add that person.';
      });
    }
  }

  Future<void> _submitDetail(String text) async {
    final separator = text.indexOf(':');
    if (separator <= 0 || separator == text.length - 1) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Use this format: Person or place: detail to remember';
      });
      return;
    }

    final entityName = text.substring(0, separator).trim();
    final detail = text.substring(separator + 1).trim();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('entities')
          .where('name', isEqualTo: entityName)
          .limit(1)
          .get();
      final id = snapshot.docs.isNotEmpty
          ? snapshot.docs.first.id
          : _normalizeEntityKey(entityName).replaceAll(' ', '_');
      final existing = snapshot.docs.isNotEmpty
          ? (snapshot.docs.first.data()['summary'] ?? '').toString()
          : '';
      await FirebaseFirestore.instance.collection('entities').doc(id).set({
        'name': entityName,
        'type': snapshot.docs.isNotEmpty
            ? (snapshot.docs.first.data()['type'] ?? 'concept')
            : 'concept',
        'summary': [
          existing,
          detail,
        ].where((item) => item.isNotEmpty).join(' '),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _textController.clear();
      if (!mounted) return;
      setState(() {
        _statusIsError = false;
        _statusMessage = 'Detail saved to $entityName. No task was created.';
      });
      await _refreshWisdomSnapshot();
    } catch (e) {
      debugPrint('Failed to save detail: $e');
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not save that detail.';
      });
    }
  }

  Widget _buildWisdomCard() {
    final entityNames = _tasks
        .expand(
          (task) => (task['linked_entities'] as List<dynamic>? ?? const [])
              .whereType<String>(),
        )
        .toList();

    final openTasks = _tasks
        .where((task) => (task['status']?.toString() ?? 'open') == 'open')
        .map((task) => (task['description'] ?? '').toString())
        .toList();

    final insight = _latestInsight.isNotEmpty
        ? InsightCard(
            summary: (_latestInsight['summary'] ?? '').toString(),
            connections:
                (((_latestInsight['connections'] as List<dynamic>?) ?? const [])
                        .map((item) {
                          if (item is Map) {
                            final entity = (item['entity'] ?? '').toString();
                            final signal = (item['signal'] ?? '').toString();
                            return entity.isNotEmpty
                                ? '• $entity: $signal'
                                : signal;
                          }
                          return item.toString();
                        })
                        .toList())
                    .cast<String>(),
            advice:
                (((_latestInsight['clusterAdvice'] as List<dynamic>?) ??
                            const [])
                        .map((item) => item.toString())
                        .toList())
                    .cast<String>(),
          )
        : _wisdomService.compileInsight(
            entityNames: entityNames,
            openTasks: openTasks,
          );

    final dailyBriefing = _wisdomService.compileDailyBriefing(
      entityNames: entityNames,
      openTasks: openTasks,
    );

    final graph = _wisdomService.compileKnowledgeGraph(
      tasks: _tasks,
      entities: _entities,
      relationships: _relationships,
    );
    final calendarEntries = _wisdomService.compileCalendar(tasks: _tasks);
    final route = _wisdomService.estimateRoutePlan(entries: calendarEntries);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily briefing',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.sunny_snowing, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dailyBriefing.headline,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            dailyBriefing.summary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_entities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_entities.length} entities loaded from Firebase memory. Open the graph or Memory panel to explore them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (dailyBriefing.priorities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Today’s priorities',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_focusFilter != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _focusFilter = null;
                    }),
                    child: const Text('Clear focus'),
                  ),
              ],
            ),
            ...dailyBriefing.priorities.map((priority) {
              final label = priority.replaceFirst(RegExp(r'^[•\s]+'), '');
              final isSelected = _focusFilter == label;

              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _focusFilter = isSelected ? null : label;
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withOpacity(0.45)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(priority),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          Text(
            'AI overview',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(insight.summary, style: Theme.of(context).textTheme.bodyMedium),
          if (graph.nodes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Connected themes',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: graph.nodes.map((node) {
                return Chip(
                  label: Text('${node.label} · ${node.weight}'),
                  avatar: const Icon(Icons.auto_awesome, size: 14),
                );
              }).toList(),
            ),
          ],
          if (route.stops.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Travel estimate',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${route.summary} Open Google Maps to see the route.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (insight.advice.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Advice',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            ...insight.advice.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $tip'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<List<ReviewItem>?> _showConfirmationDialog(
    List<ReviewItem> reviewItems,
  ) async {
    final selected = <String>{for (final item in reviewItems) item.id};

    final confirmed = await showDialog<List<ReviewItem>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Review unclear entities'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Pick the names that match this note. Unchecked entries stay in review and won’t be treated as confirmed.',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            selected.clear();
                          }),
                          child: const Text('Clear all'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            selected.addAll(reviewItems.map((item) => item.id));
                          }),
                          child: const Text('Select all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: reviewItems.map((item) {
                          final isSelected = selected.contains(item.id);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(item.label),
                            subtitle: Text(item.type),
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(item.id);
                                } else {
                                  selected.remove(item.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final confirmedItems = reviewItems
                        .where((item) => selected.contains(item.id))
                        .toList();
                    Navigator.of(context).pop(confirmedItems);
                  },
                  child: const Text('Submit note'),
                ),
              ],
            );
          },
        );
      },
    );

    return confirmed;
  }

  Future<void> _archiveTask(Map<String, dynamic> task) async {
    final id = task['id']?.toString();
    final description = (task['description'] ?? '').toString();
    final linkedEntities = task['linked_entities'] is List
        ? (task['linked_entities'] as List).whereType<String>().toList()
        : const <String>[];

    final archivedItem = {
      'description': description,
      'linked_entities': linkedEntities,
      'status': 'done',
      'completedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (id != null && id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('completed_tasks')
            .add(archivedItem);

        await FirebaseFirestore.instance
            .collection('action_items')
            .doc(id)
            .delete();
      }

      if (!mounted) return;
      setState(() {
        if (id != null && id.isNotEmpty) {
          _tasks.removeWhere((item) => item['id'] == id);
        }
        _statusMessage = 'Archived completed task.';
      });
    } catch (e) {
      debugPrint('Failed to archive task: $e');
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not archive the completed task.';
      });
    }
  }

  Future<void> _toggleTaskStatus(Map<String, dynamic> task, bool isDone) async {
    if (isDone) {
      final description = (task['description'] ?? '').toString();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Complete task?'),
          content: Text('Archive “$description” from the active list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep active'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Archive'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
    }

    final id = task['id']?.toString();
    if (id == null || id.isEmpty) {
      setState(() {
        final targetIndex = _tasks.indexWhere(
          (item) => item['id'] == task['id'],
        );
        if (targetIndex != -1) {
          if (isDone) {
            _archivedTasks = [
              ..._archivedTasks,
              Map<String, dynamic>.from(_tasks[targetIndex]),
            ];
            _tasks.removeAt(targetIndex);
          } else {
            _tasks[targetIndex]['status'] = 'open';
          }
        }
      });
      return;
    }

    if (isDone) {
      await _archiveTask(task);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('action_items')
          .doc(id)
          .update({'status': 'open'});

      setState(() {
        final targetIndex = _tasks.indexWhere((item) => item['id'] == id);
        if (targetIndex != -1) {
          _tasks[targetIndex]['status'] = 'open';
        }
      });
    } catch (e) {
      debugPrint('Failed to update task status: $e');
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not update task status.';
      });
    }
  }

  void _openMasterCalendar() {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    Navigator.of(navigatorContext).push(
      MaterialPageRoute(
        builder: (_) =>
            MasterCalendarPage(tasks: _tasks, wisdomService: _wisdomService),
      ),
    );
  }

  void _openGraphView() {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    Navigator.of(navigatorContext).push(
      MaterialPageRoute(
        builder: (_) => GraphViewPage(
          tasks: _tasks,
          entities: _entities,
          relationships: _relationships,
          wisdomService: _wisdomService,
        ),
      ),
    );
  }

  void _openAttentionView() {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    Navigator.of(navigatorContext).push(
      MaterialPageRoute(
        builder: (_) => AttentionPage(entities: _entities, tasks: _tasks),
      ),
    );
  }

  void _openInspectDashboard() {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    Navigator.of(navigatorContext).push(
      MaterialPageRoute(
        builder: (_) => InspectDashboardPage(
          entities: _entities,
          relationships: _relationships,
          tasks: _tasks,
          wisdomService: _wisdomService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Brainiac',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B6CFF),
          secondary: const Color(0xFFFF8A65),
          tertiary: const Color(0xFF26A69A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF5B6CFF),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        chipTheme: const ChipThemeData(
          selectedColor: Color(0xFF5B6CFF),
          checkmarkColor: Colors.white,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Brainiac'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5B6CFF), Color(0xFF7C4DFF), Color(0xFFFF8A65)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Open master calendar',
              icon: const Icon(Icons.calendar_month),
              onPressed: _openMasterCalendar,
            ),
            IconButton(
              tooltip: 'Open knowledge graph',
              icon: const Icon(Icons.account_tree),
              onPressed: _openGraphView,
            ),
            IconButton(
              tooltip: 'Open active attention',
              icon: const Icon(Icons.priority_high),
              onPressed: _openAttentionView,
            ),
            IconButton(
              tooltip: 'Merge duplicate entities',
              icon: const Icon(Icons.merge_type),
              onPressed: _loadDuplicateEntities,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _statusIsError
                          ? Colors.red.shade50
                          : Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusIsError
                            ? Colors.red.shade900
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InspectDashboardPage(
                    entities: _entities,
                    relationships: _relationships,
                    tasks: _tasks,
                    wisdomService: _wisdomService,
                    embedded: true,
                  ),
                ),
              ],
            ),
            if (_entityMergePanelOpen)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 360,
                child: Material(
                  elevation: 6,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Entity Dedupe',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _entityMergePanelOpen = false;
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Merge duplicate entity names into a single canonical record.',
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _entityGroups.isEmpty
                                ? const Center(
                                    child: Text('No duplicate entities found.'),
                                  )
                                : ListView.builder(
                                    itemCount: _entityGroups.length,
                                    itemBuilder: (context, index) {
                                      final group = _entityGroups[index];
                                      final names =
                                          (group['names'] as List<String>? ??
                                          const <String>[]);
                                      final primaryName = names.first;

                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                primaryName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(names.join(' • ')),
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: FilledButton(
                                                  onPressed: () =>
                                                      _mergeEntityGroup(group),
                                                  child: const Text(
                                                    'Merge duplicates',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              kBuildLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _exportState() {
    try {
      final dump = jsonEncode({
        'tasks': _tasks,
        'filter': _taskFilter.toString(),
      });
      js_bridge.context['SECOND_BRAIN_STATE'] = dump;
      debugPrint('Exported state to window.SECOND_BRAIN_STATE');
    } catch (e) {
      debugPrint('Failed to export state: $e');
    }
  }
}
