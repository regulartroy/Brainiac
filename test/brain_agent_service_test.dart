import 'package:flutter_test/flutter_test.dart';
import 'package:brainiac/services/brain_agent_service.dart';

void main() {
  test(
    'extractTasksFromNote calls the callable with note text and returns task strings',
    () async {
      dynamic capturedPayload;

      final service = BrainAgentService(
        functionCaller: (payload) async {
          capturedPayload = payload;
          return ['Review API contract', 'Book follow-up call'];
        },
      );

      final tasks = await service.extractTasksFromNote('Follow up on pitch');

      expect(capturedPayload, {
        'text': 'Follow up on pitch',
        'review_mode': false,
      });
      expect(tasks, ['Review API contract', 'Book follow-up call']);
    },
  );

  test(
    'TaskExtractionResult.fromResult handles dynamic maps from callable data',
    () {
      final result = Map<dynamic, dynamic>.from({
        'tasks': ['Review API contract'],
        'needs_context': true,
        'review_items': [
          {'id': 'alice', 'label': 'Alice', 'type': 'person'},
        ],
      });

      final extraction = TaskExtractionResult.fromResult(result);

      expect(extraction.tasks, ['Review API contract']);
      expect(extraction.needsContext, isTrue);
      expect(extraction.reviewItems, hasLength(1));
      expect(extraction.reviewItems.first.label, 'Alice');
    },
  );

  test(
    'review-flow should consider person and place candidates for disambiguation',
    () {
      final result = {
        'tasks': ['Get back to Christie'],
        'needs_context': false,
        'review_items': [
          {'id': 'christie', 'label': 'Christie', 'type': 'person'},
          {'id': 'ben', 'label': 'Ben', 'type': 'person'},
          {'id': 'studio', 'label': 'Studio A', 'type': 'venue'},
        ],
      };

      final extraction = TaskExtractionResult.fromResult(result);

      expect(extraction.needsContext, isFalse);
      expect(extraction.reviewItems, hasLength(3));
      expect(
        extraction.reviewItems.map((item) => item.type.toLowerCase()),
        containsAll(['person', 'venue']),
      );
    },
  );

  test('extractTasksForReview returns pending review candidates', () async {
    final service = BrainAgentService(
      functionCaller: (payload) async {
        expect(payload, {'text': 'Alice is the PM', 'review_mode': true});
        return {
          'tasks': ['Review timeline'],
          'needs_context': true,
          'review_items': [
            {'id': 'alice', 'label': 'Alice', 'type': 'person'},
          ],
        };
      },
    );

    final review = await service.extractTasksForReview('Alice is the PM');

    expect(review.tasks, ['Review timeline']);
    expect(review.needsContext, isTrue);
    expect(review.reviewItems, hasLength(1));
    expect(review.reviewItems.first.label, 'Alice');
  });

  test(
    'extractTasksFromNote includes selected review items when the user confirms them',
    () async {
      dynamic capturedPayload;

      final service = BrainAgentService(
        functionCaller: (payload) async {
          capturedPayload = payload;
          return ['Send follow-up to Alice'];
        },
      );

      final selected = [
        const ReviewItem(id: 'alice', label: 'Alice', type: 'person'),
        const ReviewItem(id: 'alice_b', label: 'Alice B', type: 'person'),
      ];

      final tasks = await service.extractTasksFromNote(
        'Follow up with Alice',
        selectedReviewItems: selected,
      );

      expect(capturedPayload, {
        'text': 'Follow up with Alice',
        'review_mode': false,
        'review_items': [
          {'id': 'alice', 'label': 'Alice', 'type': 'person'},
          {'id': 'alice_b', 'label': 'Alice B', 'type': 'person'},
        ],
      });
      expect(tasks, ['Send follow-up to Alice']);
    },
  );
}
