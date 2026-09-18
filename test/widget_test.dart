// Basic shell smoke test for the graph-only Brainiac home.
import 'package:flutter_test/flutter_test.dart';

import 'package:brainiac/main.dart';

void main() {
  testWidgets('SecondBrainApp renders the graph shell home', (tester) async {
    await tester.pumpWidget(const SecondBrainApp());

    expect(find.text('Brainiac'), findsWidgets);
    expect(find.text('Ready — shared memory graph'), findsOneWidget);
    expect(find.text('Entities'), findsOneWidget);
    expect(find.text('Ask Brainiac'), findsNothing);
    expect(find.text('Wisdom stream'), findsNothing);
  });
}
