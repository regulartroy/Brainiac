import 'package:brainiac/models/entity_type.dart';
import 'package:brainiac/services/curiosity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CuriosityService();

  group('EntityType.parse', () {
    test('normalizes legacy aliases', () {
      expect(EntityType.parse('organization'), EntityType.org);
      expect(EntityType.parse('location'), EntityType.area);
      expect(EntityType.parse('concept'), EntityType.other);
      expect(EntityType.parse('person'), EntityType.person);
      expect(EntityType.parse('client'), EntityType.client);
      expect(EntityType.parse('venue'), EntityType.venue);
    });
  });

  group('CuriosityService.selectQuestions', () {
    test('asks where a venue is when located_in is missing', () {
      final qs = service.selectQuestions([
        {
          'id': 'concorde_2',
          'name': 'Concorde 2',
          'type': 'venue',
          'address': 'some street',
          'located_in_entity_id': '',
        },
      ]);
      expect(qs, isNotEmpty);
      expect(qs.first.kind, 'located_in');
      expect(qs.first.prompt, contains('Concorde 2'));
      expect(qs.first.prompt.toLowerCase(), contains('town'));
    });

    test('asks for venue address when missing', () {
      final qs = service.selectQuestions([
        {
          'id': 'concorde_2',
          'name': 'Concorde 2',
          'type': 'venue',
          'address': '',
          'located_in_entity_id': 'brighton',
        },
      ]);
      expect(qs.any((q) => q.kind == 'address'), isTrue);
      final addressQ = qs.firstWhere((q) => q.kind == 'address');
      expect(addressQ.prompt.toLowerCase(), contains('address'));
    });

    test('never asks a person for a home address', () {
      final qs = service.selectQuestions([
        {
          'id': 'tom',
          'name': 'Tom',
          'type': 'person',
          'address': '',
          'located_in_entity_id': '',
        },
      ]);
      expect(qs.where((q) => q.kind == 'address'), isEmpty);
      expect(qs.where((q) => q.entityType == EntityType.person), isEmpty);
    });

    test('asks client_link when client has no org/venue edge', () {
      final qs = service.selectQuestions([
        {
          'id': 'acme',
          'name': 'Acme',
          'type': 'client',
        },
      ]);
      expect(qs.any((q) => q.kind == 'client_link'), isTrue);
    });

    test('skips client_link when relationship already exists', () {
      final qs = service.selectQuestions(
        [
          {'id': 'acme', 'name': 'Acme', 'type': 'client'},
          {'id': 'concorde', 'name': 'Concorde 2', 'type': 'venue'},
        ],
        relationships: [
          {
            'from_entity_id': 'acme',
            'to_entity_id': 'concorde',
            'type': 'client_of',
          },
        ],
      );
      expect(qs.where((q) => q.kind == 'client_link'), isEmpty);
    });

    test('caps queue at maxQuestions', () {
      final entities = List.generate(
        10,
        (i) => {
          'id': 'v$i',
          'name': 'Venue $i',
          'type': 'venue',
          'address': '',
          'located_in_entity_id': '',
        },
      );
      final qs = service.selectQuestions(entities, maxQuestions: 5);
      expect(qs.length, lessThanOrEqualTo(5));
    });
  });
}
