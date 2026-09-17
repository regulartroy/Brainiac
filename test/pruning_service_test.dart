import 'package:brainiac/services/pruning_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groupDuplicateEntities groups near-identical names together', () {
    final service = PruningService();

    final groups = service.groupDuplicateEntities([
      const EntityRecord(name: 'Alice Johnson', type: 'person', summary: 'PM'),
      const EntityRecord(name: 'Alice Johnson ', type: 'person', summary: 'PM'),
      const EntityRecord(
        name: 'Project Atlas',
        type: 'project',
        summary: 'Launch',
      ),
      const EntityRecord(
        name: 'Project Atlas!',
        type: 'project',
        summary: 'Launch',
      ),
      const EntityRecord(name: 'Studio A', type: 'venue', summary: 'Studio'),
    ]);

    expect(groups.length, 2);
    expect(groups[0].names, containsAll(['Alice Johnson', 'Alice Johnson ']));
    expect(groups[1].names, containsAll(['Project Atlas', 'Project Atlas!']));
    expect(groups[0].canonicalName, 'Alice Johnson');
    expect(groups[1].canonicalName, 'Project Atlas');
  });

  test('buildDailyQuestions returns up to five curation prompts', () {
    final service = PruningService();

    final questions = service.buildDailyQuestions([
      const EntityRecord(name: 'Alice Johnson', type: 'person', summary: 'PM'),
      const EntityRecord(
        name: 'Project Atlas',
        type: 'project',
        summary: 'Launch',
      ),
      const EntityRecord(name: 'Studio A', type: 'venue', summary: 'HQ'),
      const EntityRecord(name: 'Roadmap', type: 'concept', summary: 'Planning'),
      const EntityRecord(
        name: 'Miro Board',
        type: 'equipment',
        summary: 'Planning board',
      ),
      const EntityRecord(name: 'Notion', type: 'equipment', summary: 'Docs'),
    ]);

    expect(questions.length, 5);
    expect(questions.first, contains('Alice Johnson'));
    expect(questions, everyElement(contains('What next step connects')));
  });

  test(
    'compressTodoList groups repeated tasks by entity and keeps a count',
    () {
      final service = PruningService();

      final compressed = service.compressTodoList([
        {
          'description': 'Follow up with Alice Johnson',
          'linked_entities': ['Alice Johnson'],
          'status': 'open',
        },
        {
          'description': 'Send Alice Johnson an update',
          'linked_entities': ['Alice Johnson'],
          'status': 'open',
        },
        {
          'description': 'Book studio time',
          'linked_entities': ['Studio A'],
          'status': 'open',
        },
      ]);

      expect(compressed.length, 2);
      expect(compressed.first['description'], contains('Alice Johnson'));
      expect(compressed.first['description'], contains('2 tasks'));
      expect(compressed.first['linked_entities'], contains('Alice Johnson'));
    },
  );

  test('rewriteLinkedEntities remaps alias names and ids onto canonical', () {
    final service = PruningService();
    final result = service.rewriteLinkedEntities(
      linkedEntities: ['Alice Johnson ', 'Studio A', 'Alice Johnson'],
      linkedEntityIds: ['alice_johnson_', 'studio_a', 'alice-johnson'],
      aliasNames: {'Alice Johnson', 'Alice Johnson '},
      aliasIds: {'alice_johnson_', 'alice-johnson', 'alice_johnson'},
      canonicalName: 'Alice Johnson',
      canonicalId: 'alice_johnson',
    );

    expect(result.changed, isTrue);
    expect(result.linkedEntities, ['Alice Johnson', 'Studio A']);
    expect(result.linkedEntityIds, ['alice_johnson', 'studio_a']);
  });

  test('rewriteRelationship remaps aliases and drops self-loops', () {
    final service = PruningService();
    final remapped = service.rewriteRelationship(
      fromEntity: 'Alice Johnson!',
      toEntity: 'Project Atlas',
      fromEntityId: 'alice_dup',
      toEntityId: 'project_atlas',
      type: 'works_on',
      canonicalNameByKey: {
        PruningService.normalizeEntityKey('Alice Johnson!'): 'Alice Johnson',
      },
      canonicalIdByAlias: {'alice_dup': 'alice_johnson'},
    );

    expect(remapped.changed, isTrue);
    expect(remapped.drop, isFalse);
    expect(remapped.fromEntity, 'Alice Johnson');
    expect(remapped.fromEntityId, 'alice_johnson');
    expect(remapped.edgeKey, contains('alice johnson'));

    final selfLoop = service.rewriteRelationship(
      fromEntity: 'Alice Johnson!',
      toEntity: 'Alice Johnson',
      fromEntityId: 'alice_dup',
      toEntityId: 'alice_johnson',
      type: 'related',
      canonicalNameByKey: {
        PruningService.normalizeEntityKey('Alice Johnson!'): 'Alice Johnson',
        PruningService.normalizeEntityKey('Alice Johnson'): 'Alice Johnson',
      },
      canonicalIdByAlias: {
        'alice_dup': 'alice_johnson',
        'alice_johnson': 'alice_johnson',
      },
    );

    expect(selfLoop.drop, isTrue);
  });
}
