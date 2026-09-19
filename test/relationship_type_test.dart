import 'package:brainiac/models/entity_type.dart';
import 'package:brainiac/models/relationship_type.dart';
import 'package:brainiac/services/relationship_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RelationshipType.forSourceEntity', () {
    test('person gets freelances_for, works_at, client_of, knows', () {
      final types = RelationshipType.forSourceEntity(EntityType.person);
      expect(
        types.map((t) => t.firestoreValue).toList(),
        containsAll(['freelances_for', 'works_at', 'client_of', 'knows']),
      );
      expect(types.length, 4);
      // freelances_for is preferred default ahead of works_at
      expect(types.first, RelationshipType.freelancesFor);
    });

    test('defaultForSource prefers freelances_for for person', () {
      expect(
        RelationshipType.defaultForSource(EntityType.person),
        RelationshipType.freelancesFor,
      );
    });

    test('client gets client_of only', () {
      final types = RelationshipType.forSourceEntity(EntityType.client);
      expect(types.map((t) => t.firestoreValue).toList(), ['client_of']);
    });

    test('venue does not get knows or works_at as source', () {
      final types = RelationshipType.forSourceEntity(EntityType.venue);
      expect(types, isEmpty);
    });

    test('org and area have no outgoing v1 types', () {
      expect(RelationshipType.forSourceEntity(EntityType.org), isEmpty);
      expect(RelationshipType.forSourceEntity(EntityType.area), isEmpty);
    });
  });

  group('RelationshipType target filters', () {
    test('freelances_for targets org/venue/client', () {
      expect(
        RelationshipType.freelancesFor.allowedToTypes,
        containsAll([EntityType.org, EntityType.venue, EntityType.client]),
      );
    });

    test('works_at targets org/venue/client', () {
      expect(
        RelationshipType.worksAt.allowedToTypes,
        containsAll([EntityType.org, EntityType.venue, EntityType.client]),
      );
    });

    test('knows targets person only', () {
      expect(RelationshipType.knows.allowedToTypes, [EntityType.person]);
    });

    test('client_of targets org/venue', () {
      expect(
        RelationshipType.clientOf.allowedToTypes,
        containsAll([EntityType.org, EntityType.venue]),
      );
    });
  });

  group('RelationshipService.targetOptions', () {
    final entities = [
      {'id': 'tom', 'name': 'Tom Burch (Me)', 'type': 'person'},
      {
        'id': 'concorde_2',
        'name': 'Concorde 2',
        'type': 'venue',
        'roles': ['client'],
      },
      {'id': 'brighton', 'name': 'Brighton', 'type': 'area'},
      {'id': 'acme', 'name': 'Acme', 'type': 'client'},
      {'id': 'other_person', 'name': 'Alex', 'type': 'person'},
    ];

    test('freelances_for from Tom lists Concorde 2 and Acme', () {
      final opts = RelationshipService.targetOptions(
        type: RelationshipType.freelancesFor,
        allEntities: entities,
        sourceId: 'tom',
      );
      final ids = opts.map((e) => e['id']).toList();
      expect(ids, containsAll(['concorde_2', 'acme']));
      expect(ids, isNot(contains('brighton')));
      expect(ids, isNot(contains('tom')));
      expect(ids, isNot(contains('other_person')));
    });

    test('works_at from Tom lists Concorde 2 and Acme, not Brighton/people', () {
      final opts = RelationshipService.targetOptions(
        type: RelationshipType.worksAt,
        allEntities: entities,
        sourceId: 'tom',
      );
      final ids = opts.map((e) => e['id']).toList();
      expect(ids, containsAll(['concorde_2', 'acme']));
      expect(ids, isNot(contains('brighton')));
      expect(ids, isNot(contains('tom')));
      expect(ids, isNot(contains('other_person')));
    });

    test('knows from Tom lists other people only', () {
      final opts = RelationshipService.targetOptions(
        type: RelationshipType.knows,
        allEntities: entities,
        sourceId: 'tom',
      );
      expect(opts.map((e) => e['id']).toList(), ['other_person']);
    });
  });

  group('RelationshipService.edgesForEntity / readableLabel', () {
    final rels = [
      {
        'id': 'r1',
        'from_entity_id': 'tom',
        'from_entity': 'Tom Burch (Me)',
        'to_entity_id': 'concorde_2',
        'to_entity': 'Concorde 2',
        'type': 'freelances_for',
      },
    ];

    test('finds edge by entity id', () {
      final edges = RelationshipService.edgesForEntity(
        relationships: rels,
        entityId: 'tom',
        entityName: 'Tom Burch (Me)',
      );
      expect(edges, hasLength(1));
    });

    test('readable label from person side', () {
      final label = RelationshipService.readableLabel(
        rels.first,
        viewerId: 'tom',
        viewerName: 'Tom Burch (Me)',
      );
      expect(label, 'freelances for Concorde 2');
    });

    test('readable label from venue side', () {
      final label = RelationshipService.readableLabel(
        rels.first,
        viewerId: 'concorde_2',
        viewerName: 'Concorde 2',
      );
      expect(label, 'Tom Burch (Me) freelances for this');
    });
  });

  group('RelationshipType.tryParse', () {
    test('parses canonical strings', () {
      expect(
        RelationshipType.tryParse('freelances_for'),
        RelationshipType.freelancesFor,
      );
      expect(RelationshipType.tryParse('works_at'), RelationshipType.worksAt);
      expect(RelationshipType.tryParse('client_of'), RelationshipType.clientOf);
      expect(RelationshipType.tryParse('knows'), RelationshipType.knows);
      expect(RelationshipType.tryParse('located_in'), isNull);
    });
  });
}
