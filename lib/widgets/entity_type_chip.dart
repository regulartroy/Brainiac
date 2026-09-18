import 'package:flutter/material.dart';

import '../models/entity_type.dart';

class EntityTypeChip extends StatelessWidget {
  const EntityTypeChip({
    super.key,
    required this.type,
    this.selected = false,
    this.onSelected,
    this.showIcon = true,
    this.compact = false,
  });

  final EntityType type;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool showIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? type.color : type.softBackground;
    final fg = selected ? Colors.white : type.color;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          Icon(type.icon, size: compact ? 14 : 16, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          type.label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 12 : 13,
          ),
        ),
      ],
    );

    if (onSelected != null) {
      return FilterChip(
        selected: selected,
        onSelected: onSelected,
        selectedColor: type.color,
        backgroundColor: type.softBackground,
        checkmarkColor: Colors.white,
        label: label,
        visualDensity:
            compact ? VisualDensity.compact : VisualDensity.standard,
        side: BorderSide(color: type.color.withValues(alpha: 0.45)),
      );
    }

    return Chip(
      avatar: showIcon
          ? Icon(type.icon, size: 16, color: selected ? Colors.white : type.color)
          : null,
      label: Text(
        type.label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 12 : 13,
        ),
      ),
      backgroundColor: bg,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      side: BorderSide(color: type.color.withValues(alpha: 0.35)),
      padding: compact ? EdgeInsets.zero : null,
    );
  }
}
