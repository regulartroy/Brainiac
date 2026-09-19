import 'package:brainiac/models/entity_roles.dart';
import 'package:brainiac/models/entity_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntityRoles.parse', () {
    test('handles null and non-lists', () {
      expect(EntityRoles.parse(null), isEmpty);
      expect(EntityRoles.parse('client'), isEmpty);
    });

    test('normalizes and dedupes', () {
      expect(
        EntityRoles.parse(['Client', 'client', '  ', 'other']),
        ['client', 'other'],
      );
    });
  });

  group('EntityRoles.isClientFacet', () {
    test('true for primary type client', () {
      expect(
        EntityRoles.isClientFacet({'type': 'client', 'roles': []}),
        isTrue,
      );
    });

    test('true for venue with client role', () {
      expect(
        EntityRoles.isClientFacet({
          'type': 'venue',
          'roles': ['client'],
        }),
        isTrue,
      );
    });

    test('false for plain venue', () {
      expect(
        EntityRoles.isClientFacet({'type': 'venue', 'roles': []}),
        isFalse,
      );
    });
  });

  group('EntityRoles.canToggleClientRole', () {
    test('venue/org/person yes, client/area no', () {
      expect(EntityRoles.canToggleClientRole(EntityType.venue), isTrue);
      expect(EntityRoles.canToggleClientRole(EntityType.org), isTrue);
      expect(EntityRoles.canToggleClientRole(EntityType.person), isTrue);
      expect(EntityRoles.canToggleClientRole(EntityType.client), isFalse);
      expect(EntityRoles.canToggleClientRole(EntityType.area), isFalse);
    });
  });

  group('EntityRoles.withRole', () {
    test('adds and removes client', () {
      expect(
        EntityRoles.withRole([], role: EntityRoles.client, enabled: true),
        ['client'],
      );
      expect(
        EntityRoles.withRole(
          ['client'],
          role: EntityRoles.client,
          enabled: false,
        ),
        isEmpty,
      );
    });
  });
}
