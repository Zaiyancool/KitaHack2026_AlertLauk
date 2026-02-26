import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(CampusSafetyApp());

    // Verify that app title is shown
    expect(find.text('Alert Lauk'), findsOneWidget);
  });
}
