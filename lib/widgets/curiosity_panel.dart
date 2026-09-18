import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/entity_type.dart';
import '../services/curiosity_service.dart';
import '../services/pruning_service.dart';
import 'entity_type_chip.dart';

/// Calm 1–5 question queue to fill missing graph blanks.
class CuriosityPanel extends StatefulWidget {
  const CuriosityPanel({
    super.key,
    required this.entities,
    required this.relationships,
  });

  final List<Map<String, dynamic>> entities;
  final List<Map<String, dynamic>> relationships;

  @override
  State<CuriosityPanel> createState() => _CuriosityPanelState();
}

class _CuriosityPanelState extends State<CuriosityPanel> {
  static const _service = CuriosityService();
  final _answer = TextEditingController();
  String? _activeId;
  bool _saving = false;
  final Set<String> _dismissed = {};

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  List<CuriosityQuestion> get _questions {
    return _service
        .selectQuestions(
          widget.entities,
          relationships: widget.relationships,
        )
        .where((q) => !_dismissed.contains(q.id))
        .toList();
  }

  Future<void> _applyAnswer(CuriosityQuestion q, String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final entityRef =
          FirebaseFirestore.instance.collection('entities').doc(q.entityId);

      if (q.kind == 'address') {
        // Places only — guard even if UI mis-routes.
        if (!q.entityType.isPlace) {
          throw StateError('Address is only for areas/venues.');
        }
        await entityRef.set({
          'address': text,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (q.kind == 'located_in') {
        final areaId = await _ensureAreaEntity(text);
        await entityRef.set({
          'located_in_entity_id': areaId,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (q.kind == 'client_link') {
        final target = await _ensureOrgOrVenue(text);
        await FirebaseFirestore.instance.collection('relationships').add({
          'from_entity_id': q.entityId,
          'from_entity': q.entityName,
          'to_entity_id': target['id'],
          'to_entity': target['name'],
          'type': 'client_of',
          'summary': '${q.entityName} ↔ ${target['name']}',
          'labels': ['client_link'],
          'last_updated': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      setState(() {
        _dismissed.add(q.id);
        _activeId = null;
        _answer.clear();
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<String> _ensureAreaEntity(String name) async {
    final existing = widget.entities.where((e) {
      final n = (e['name'] ?? '').toString().toLowerCase();
      final t = EntityType.parse(e['type']?.toString());
      return n == name.toLowerCase() && t == EntityType.area;
    });
    if (existing.isNotEmpty) {
      return existing.first['id'].toString();
    }
    // Also match any entity with same name and promote to area if needed.
    final byName = widget.entities.where(
      (e) =>
          (e['name'] ?? '').toString().toLowerCase() == name.toLowerCase(),
    );
    if (byName.isNotEmpty) {
      final id = byName.first['id'].toString();
      await FirebaseFirestore.instance.collection('entities').doc(id).set({
        'type': EntityType.area.firestoreValue,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return id;
    }
    final id = PruningService.entityIdForName(name);
    await FirebaseFirestore.instance.collection('entities').doc(id).set({
      'name': name.trim(),
      'type': EntityType.area.firestoreValue,
      'summary': '',
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  Future<Map<String, String>> _ensureOrgOrVenue(String name) async {
    final match = widget.entities.where((e) {
      final n = (e['name'] ?? '').toString().toLowerCase();
      final t = EntityType.parse(e['type']?.toString());
      return n == name.toLowerCase() &&
          (t == EntityType.org || t == EntityType.venue || t == EntityType.client);
    });
    if (match.isNotEmpty) {
      return {
        'id': match.first['id'].toString(),
        'name': match.first['name'].toString(),
      };
    }
    final byName = widget.entities.where(
      (e) =>
          (e['name'] ?? '').toString().toLowerCase() == name.toLowerCase(),
    );
    if (byName.isNotEmpty) {
      return {
        'id': byName.first['id'].toString(),
        'name': byName.first['name'].toString(),
      };
    }
    final id = PruningService.entityIdForName(name);
    final display = name.trim();
    await FirebaseFirestore.instance.collection('entities').doc(id).set({
      'name': display,
      'type': EntityType.org.firestoreValue,
      'summary': '',
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return {'id': id, 'name': display};
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;
    if (questions.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: scheme.secondaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.secondary),
                const SizedBox(width: 6),
                Text(
                  'Curiosity',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSecondaryContainer,
                      ),
                ),
                const Spacer(),
                Text(
                  '${questions.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A few gentle blanks to fill — skip anytime.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
            ),
            const SizedBox(height: 8),
            ...questions.map((q) => _buildQuestion(q)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(CuriosityQuestion q) {
    final active = _activeId == q.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EntityTypeChip(type: q.entityType, compact: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.prompt,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Skip',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _dismissed.add(q.id)),
                  ),
                ],
              ),
              if (!active)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _activeId = q.id;
                      _answer.clear();
                    }),
                    child: const Text('Answer'),
                  ),
                )
              else ...[
                if (q.hint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      q.hint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _answer,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'Type a short answer',
                        ),
                        onSubmitted: _saving
                            ? null
                            : (v) => _applyAnswer(q, v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _applyAnswer(q, _answer.text),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
