import 'package:flutter/material.dart';

/// Canonical entity types for the typed life graph.
enum EntityType {
  person,
  org,
  client,
  area,
  venue,
  other;

  String get label {
    switch (this) {
      case EntityType.person:
        return 'Person';
      case EntityType.org:
        return 'Org';
      case EntityType.client:
        return 'Client';
      case EntityType.area:
        return 'Area';
      case EntityType.venue:
        return 'Venue';
      case EntityType.other:
        return 'Other';
    }
  }

  String get firestoreValue => name;

  IconData get icon {
    switch (this) {
      case EntityType.person:
        return Icons.person;
      case EntityType.org:
        return Icons.business;
      case EntityType.client:
        return Icons.handshake;
      case EntityType.area:
        return Icons.location_city;
      case EntityType.venue:
        return Icons.place;
      case EntityType.other:
        return Icons.category;
    }
  }

  /// Distinct, saturated colours for visual differentiation.
  Color get color {
    switch (this) {
      case EntityType.person:
        return const Color(0xFF5B6CFF); // indigo-blue
      case EntityType.org:
        return const Color(0xFF7C4DFF); // deep purple
      case EntityType.client:
        return const Color(0xFF00897B); // teal
      case EntityType.area:
        return const Color(0xFF43A047); // green
      case EntityType.venue:
        return const Color(0xFFE65100); // deep orange
      case EntityType.other:
        return const Color(0xFF6D4C41); // brown
    }
  }

  Color get softBackground => color.withValues(alpha: 0.14);

  bool get isPlace => this == EntityType.area || this == EntityType.venue;

  static const List<EntityType> all = EntityType.values;

  /// Normalize legacy / free-form type strings into the canonical set.
  static EntityType parse(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case 'person':
      case 'people':
        return EntityType.person;
      case 'org':
      case 'organization':
      case 'organisation':
      case 'company':
        return EntityType.org;
      case 'client':
        return EntityType.client;
      case 'area':
      case 'town':
      case 'city':
      case 'location':
        return EntityType.area;
      case 'venue':
      case 'building':
      case 'place':
        return EntityType.venue;
      case 'other':
      case 'concept':
      case 'project':
      case 'equipment':
      case 'entity':
      case '':
        return EntityType.other;
      default:
        return EntityType.other;
    }
  }
}
