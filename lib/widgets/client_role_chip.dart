import 'package:flutter/material.dart';

import '../models/entity_type.dart';

/// Compact badge shown when an entity has the client role facet.
class ClientRoleChip extends StatelessWidget {
  const ClientRoleChip({
    super.key,
    this.compact = true,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = EntityType.client;
    final fg = type.color;
    return Chip(
      avatar: Icon(type.icon, size: compact ? 14 : 16, color: fg),
      label: Text(
        'Client',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 12 : 13,
        ),
      ),
      backgroundColor: type.softBackground,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      side: BorderSide(color: type.color.withValues(alpha: 0.35)),
      padding: compact ? EdgeInsets.zero : null,
    );
  }
}
