import 'package:flutter_test/flutter_test.dart';

import 'package:whatsapp_controller/main.dart';

void main() {
  testWidgets('Smoke test - finds app bar title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StealthApp());

    // Verify that our app bar title is displayed.
    expect(find.text('Stealth Responder Control'), findsOneWidget);
  });
}
