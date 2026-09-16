// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:brainiac/main.dart';

void main() {
  testWidgets('SecondBrainApp renders the main app shell', (tester) async {
    await tester.pumpWidget(const SecondBrainApp());

    expect(find.text('Brainiac Test'), findsOneWidget);
    expect(
      find.text('Ready — your memory is compressed into insight'),
      findsOneWidget,
    );
  });
}
