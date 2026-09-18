import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/entity_type.dart';
import '../services/pruning_service.dart';
import 'entity_type_chip.dart';

/// Create or edit an entity with a forced canonical type.
Future<bool> showEntityEditorSheet(
  BuildContext context, {
  Map<String, dynamic>? existing,
  required List<Map<String, dynamic>> allEntities,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _EntityEditorSheet(
      existing: existing,
      allEntities: allEntities,
    ),
  );
  return result == true;
}

class _EntityEditorSheet extends StatefulWidget {
  const _EntityEditorSheet({
    this.existing,
    required this.allEntities,
  });

  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> allEntities;

  @override
  State<_EntityEditorSheet> createState() => _EntityEditorSheetState();
}

class _EntityEditorSheetState extends State<_EntityEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _summary;
  late final TextEditingController _address;
  late EntityType _type;
  String? _locatedInId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: (e?['name'] ?? '').toString());
    _summary = TextEditingController(text: (e?['summary'] ?? '').toString());
    _address = TextEditingController(text: (e?['address'] ?? '').toString());
    _type = EntityType.parse(e?['type']?.toString());
    final loc = (e?['located_in_entity_id'] ?? '').toString();
    _locatedInId = loc.isEmpty ? null : loc;
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _address.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _areaOptions {
    return widget.allEntities.where((e) {
      return EntityType.parse(e['type']?.toString()) == EntityType.area;
    }).toList()
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()),
      );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = _isEdit
          ? (widget.existing!['id'] ?? '').toString()
          : PruningService.entityIdForName(name);
      if (id.isEmpty) {
        setState(() {
          _saving = false;
          _error = 'Could not derive an id.';
        });
        return;
      }

      final data = <String, dynamic>{
        'name': name,
        'type': _type.firestoreValue,
        'summary': _summary.text.trim(),
        'last_updated': FieldValue.serverTimestamp(),
      };

      if (_type.isPlace) {
        data['address'] = _address.text.trim();
      } else {
        // Do not keep place-only fields on people/orgs/clients.
        data['address'] = FieldValue.delete();
      }

      if (_type == EntityType.venue) {
        data['located_in_entity_id'] = _locatedInId ?? '';
      } else {
        data['located_in_entity_id'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance
          .collection('entities')
          .doc(id)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEdit ? 'Edit entity' : 'New entity',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            Text(
              'Type',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: EntityType.all.map((t) {
                return EntityTypeChip(
                  type: t,
                  selected: _type == t,
                  compact: true,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(
                labelText: 'Summary (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            if (_type.isPlace) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: InputDecoration(
                  labelText: _type == EntityType.venue
                      ? 'Address (optional)'
                      : 'Address / note (optional)',
                  border: const OutlineInputBorder(),
                  helperText: _type == EntityType.person
                      ? null
                      : 'Places only — never used for people',
                ),
              ),
            ],
            if (_type == EntityType.venue) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Located in (area)',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _locatedInId,
                    hint: const Text('— none yet —'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— none yet —'),
                      ),
                      ..._areaOptions.map(
                        (a) => DropdownMenuItem<String?>(
                          value: a['id']?.toString(),
                          child: Text((a['name'] ?? '').toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _locatedInId = v),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isEdit ? 'Save' : 'Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
