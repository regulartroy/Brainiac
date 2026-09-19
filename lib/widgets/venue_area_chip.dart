import 'package:flutter/material.dart';

import '../models/entity_type.dart';
import '../services/relationship_service.dart';

/// Prominent venue → area affordance: “in {Area}” or “Set area”.
class VenueAreaChip extends StatelessWidget {
  const VenueAreaChip({
    super.key,
    required this.venue,
    required this.allEntities,
    this.onChanged,
  });

  final Map<String, dynamic> venue;
  final List<Map<String, dynamic>> allEntities;
  final VoidCallback? onChanged;

  String get _venueId => (venue['id'] ?? '').toString();
  String get _locatedInId =>
      (venue['located_in_entity_id'] ?? '').toString().trim();

  String? get _areaName {
    if (_locatedInId.isEmpty) return null;
    for (final e in allEntities) {
      if ((e['id'] ?? '').toString() == _locatedInId) {
        return (e['name'] ?? _locatedInId).toString();
      }
    }
    return _locatedInId;
  }

  List<Map<String, dynamic>> get _areas {
    return allEntities.where((e) {
      return EntityType.parse(e['type']?.toString()) == EntityType.area;
    }).toList()
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()),
      );
  }

  Future<void> _pickArea(BuildContext context) async {
    if (_venueId.isEmpty) return;
    final areas = _areas;
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set area for ${(venue['name'] ?? 'venue').toString()}',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (areas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No areas yet — create an Area entity (e.g. Brighton) first.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.clear),
                          title: const Text('— none —'),
                          onTap: () => Navigator.pop(ctx, ''),
                        ),
                        ...areas.map((a) {
                          final id = a['id']?.toString() ?? '';
                          final name = a['name']?.toString() ?? '';
                          final selected = id == _locatedInId;
                          return ListTile(
                            leading: Icon(
                              Icons.location_city,
                              color: EntityType.area.color,
                            ),
                            title: Text(name),
                            trailing: selected
                                ? const Icon(Icons.check_circle)
                                : null,
                            onTap: () => Navigator.pop(ctx, id),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null) return;
    try {
      await const RelationshipService().setLocatedIn(
        venueId: _venueId,
        areaId: chosen.isEmpty ? null : chosen,
      );
      onChanged?.call();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set area: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _areaName;
    final hasArea = name != null && name.isNotEmpty;
    final color = EntityType.area.color;

    return ActionChip(
      avatar: Icon(
        hasArea ? Icons.location_on : Icons.add_location_alt_outlined,
        size: 16,
        color: hasArea ? color : Theme.of(context).colorScheme.outline,
      ),
      label: Text(
        hasArea ? 'in $name' : 'Set area',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: hasArea ? color : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: hasArea
          ? EntityType.area.softBackground
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: hasArea
            ? color.withValues(alpha: 0.45)
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        style: hasArea ? BorderStyle.solid : BorderStyle.solid,
      ),
      visualDensity: VisualDensity.compact,
      onPressed: () => _pickArea(context),
    );
  }
}
