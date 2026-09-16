import 'package:brainiac/services/wisdom_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compileInsightSummary turns graph state into a concise wisdom summary',
    () {
      final service = WisdomService();

      final insight = service.compileInsight(
        entityNames: const ['Alice Johnson', 'Project Atlas', 'Studio A'],
        openTasks: const ['Follow up with Alice', 'Ship launch checklist'],
      );

      expect(insight.summary, contains('2 active tasks remain in motion'));
      expect(insight.summary, contains('3 entities'));
      expect(insight.connections, hasLength(3));
      expect(insight.connections.first, contains('Alice Johnson'));
    },
  );

  test(
    'compileInsight groups repeated task clusters into actionable advice',
    () {
      final service = WisdomService();

      final insight = service.compileInsight(
        entityNames: const [
          'Alice Johnson',
          'Alice Johnson',
          'Alice Johnson',
          'Studio A',
        ],
        openTasks: const [
          'Follow up with Alice Johnson',
          'Send Alice Johnson an update',
          'Book studio time',
        ],
      );

      expect(insight.advice, anyElement(contains('Alice Johnson')));
      expect(
        insight.advice.any(
          (item) => item.contains('batch') || item.contains('single follow-up'),
        ),
        isTrue,
      );
    },
  );

  test(
    'compileDailyBriefing produces a concise daily focus and action prompts',
    () {
      final service = WisdomService();

      final briefing = service.compileDailyBriefing(
        entityNames: const ['Alice Johnson', 'Studio A', 'Studio A'],
        openTasks: const [
          'Follow up with Alice Johnson',
          'Send Alice Johnson an update',
          'Book studio time',
          'Draft launch checklist',
        ],
      );

      expect(briefing.headline, contains('Alice Johnson'));
      expect(briefing.priorities, hasLength(3));
      expect(briefing.priorities.first, contains('Alice Johnson'));
      expect(briefing.summary, contains('focus'));
    },
  );

  test('compileCalendar groups tasks by client, category and place', () {
    final service = WisdomService();

    final calendar = service.compileCalendar(
      tasks: [
        {
          'description': 'Follow up with Acme client',
          'linked_entities': ['Acme', 'Alice Johnson'],
          'status': 'open',
          'category': 'Client work',
          'place': '123 Market Street',
          'startAt': '2026-09-10T09:00:00Z',
        },
        {
          'description': 'Review design sprint',
          'linked_entities': ['Studio A'],
          'status': 'open',
          'category': 'Project',
          'place': 'Studio A',
          'startAt': '2026-09-10T14:00:00Z',
        },
      ],
      now: DateTime(2026, 9, 9),
    );

    expect(calendar, isNotEmpty);
    expect(calendar.first.client, 'Acme');
    expect(calendar.first.category, 'Client work');
    expect(calendar.first.place, '123 Market Street');
  });

  test('estimateRoutePlan totals travel time for multi-stop day', () {
    final service = WisdomService();

    final route = service.estimateRoutePlan(
      entries: [
        const CalendarEntry(
          title: 'Acme call',
          client: 'Acme',
          category: 'Client work',
          place: '123 Market Street',
          startsAt: null,
        ),
        const CalendarEntry(
          title: 'Studio sprint',
          client: 'Studio A',
          category: 'Project',
          place: '42 West Ave',
          startsAt: null,
        ),
      ],
    );

    expect(route.stopCount, 2);
    expect(route.totalMinutes, greaterThanOrEqualTo(25));
    expect(route.summary, contains('2 stops'));
  });

  test('answerQuestion summarises the compressed memory in plain language', () {
    final service = WisdomService();

    final reply = service.answerQuestion(
      question: 'What do I have on for Acme this month?',
      tasks: [
        {
          'description': 'Follow up with Acme',
          'linked_entities': ['Acme'],
          'status': 'open',
          'category': 'Client work',
          'place': '123 Market Street',
          'startAt': '2026-09-10T09:00:00Z',
        },
        {
          'description': 'Draft launch plan',
          'linked_entities': ['Studio A'],
          'status': 'open',
          'category': 'Project',
          'place': 'Studio A',
          'startAt': '2026-09-11T10:00:00Z',
        },
      ],
    );

    expect(reply.answer, contains('Acme'));
    expect(reply.highlights, isNotEmpty);
  });
}
