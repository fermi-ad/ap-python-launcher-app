// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:ap_python_launcher_app/main.dart' show ApPythonLauncherApp;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds', (final tester) async {
    await tester.pumpWidget(const ApPythonLauncherApp());
    expect(find.text('AP Python Launcher'), findsOneWidget);
  });
}
