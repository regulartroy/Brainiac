import 'package:flutter/material.dart';

import '../models/entity_type.dart';
import '../models/relationship_type.dart';
import '../services/relationship_service.dart';
import 'entity_type_chip.dart';

/// Thin “Links” list + add/remove for an entity’s relationship edges.
class EntityLinksSection extends StatelessWidget {
  const EntityLinksSection({
    super.key,
    required this.entity,
    required this.allEntities,
    required this.relationships,
  });

  final Map<String, dynamic> entity;
  final List<Map<String, dynamic>> allEntities;
  final List<Map<String, dynamic>> relationships;

  String get _id => (entity['id'] ?? '').toString();
  String get _name => (entity['name'] ?? '').toString();
  EntityType get _type => EntityType.parse(entity['type']?.toString());

  List<Map<String, dynamic>> get _edges => RelationshipService.edgesForEntity(
        relationships: relationships,
        entityId: _id,
        entityName: _name,
      );

  List<RelationshipType> get _addableTypes =>
      RelationshipType.forSourceEntity(_type);

  Future<void> _addLink(BuildContext context) async {
    if (_id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the entity before adding links.')),
      );
      return;
    }
    final types = _addableTypes;
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No link types for ${_type.label.toLowerCase()}s yet.'),
        ),
      );
      return;
    }

    final result = await showDialog<_AddLinkResult>(
      context: context,
      builder: (ctx) => _AddLinkDialog(
        sourceId: _id,
        sourceName: _name,
        sourceType: _type,
        allowedTypes: types,
        allEntities: allEntities,
      ),
    );
    if (result == null) return;

    try {
      await const RelationshipService().addLink(
        fromEntityId: _id,
        fromEntity: _name,
        toEntityId: result.toId,
        toEntity: result.toName,
        type: result.type,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Linked: $_name ${result.type.verb} ${result.toName}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add link: $e')),
        );
      }
    }
  }

  Future<void> _removeLink(
    BuildContext context,
    Map<String, dynamic> rel,
  ) async {
    final id = (rel['id'] ?? '').toString();
    if (id.isEmpty) return;
    final label = RelationshipService.readableLabel(
      rel,
      viewerId: _id,
      viewerName: _name,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove link?'),
        content: Text(label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await const RelationshipService().removeLink(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final edges = _edges;
    final canAdd = _addableTypes.isNotEmpty && _id.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Links',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (canAdd)
              TextButton.icon(
                onPressed: () => _addLink(context),
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text('Add link'),
              ),
          ],
        ),
        if (edges.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              canAdd
                  ? 'No links yet — add works-at, client-of, or knows.'
                  : 'No links involving this entity.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...edges.map((rel) {
            final label = RelationshipService.readableLabel(
              rel,
              viewerId: _id,
              viewerName: _name,
            );
            final typed =
                RelationshipType.tryParse(rel['type']?.toString());
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.link,
                size: 20,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              title: Text(label),
              subtitle: typed == null
                  ? null
                  : Text(typed.label, style: Theme.of(context).textTheme.bodySmall),
              trailing: (rel['id'] ?? '').toString().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Remove link',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeLink(context, rel),
                    ),
            );
          }),
      ],
    );
  }
}

class _AddLinkResult {
  const _AddLinkResult({
    required this.type,
    required this.toId,
    required this.toName,
  });

  final RelationshipType type;
  final String toId;
  final String toName;
}

class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog({
    required this.sourceId,
    required this.sourceName,
    required this.sourceType,
    required this.allowedTypes,
    required this.allEntities,
  });

  final String sourceId;
  final String sourceName;
  final EntityType sourceType;
  final List<RelationshipType> allowedTypes;
  final List<Map<String, dynamic>> allEntities;

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  late RelationshipType _type;
  String? _toId;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _type = widget.allowedTypes.first;
  }

  List<Map<String, dynamic>> get _targets {
    final opts = RelationshipService.targetOptions(
      type: _type,
      allEntities: widget.allEntities,
      sourceId: widget.sourceId,
    );
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return opts;
    return opts
        .where((e) => (e['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    return AlertDialog(
      title: Text('Add link from ${widget.sourceName}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relationship',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.allowedTypes.map((t) {
                final selected = _type == t;
                return FilterChip(
                  selected: selected,
                  label: Text(t.label),
                  onSelected: (_) => setState(() {
                    _type = t;
                    _toId = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Find target',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: targets.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No matching entities.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: targets.length,
                      itemBuilder: (context, index) {
                        final e = targets[index];
                        final id = e['id']?.toString() ?? '';
                        final name = e['name']?.toString() ?? '';
                        final type = EntityType.parse(e['type']?.toString());
                        final selected = _toId == id;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: EntityTypeChip(
                            type: type,
                            compact: true,
                            showIcon: true,
                          ),
                          title: Text(name),
                          onTap: () => setState(() => _toId = id),
                          trailing: selected
                              ? const Icon(Icons.check_circle, size: 20)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _toId == null
              ? null
              : () {
                  String name = '';
                  for (final e in widget.allEntities) {
                    if (e['id']?.toString() == _toId) {
                      name = e['name']?.toString() ?? '';
                      break;
                    }
                  }
                  Navigator.pop(
                    context,
                    _AddLinkResult(
                      type: _type,
                      toId: _toId!,
                      toName: name,
                    ),
                  );
                },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
