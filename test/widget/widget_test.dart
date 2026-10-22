import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:ap_python_launcher_app/main.dart' show ApPythonLauncherApp;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds', (final tester) async {
    await tester.pumpWidget(const ApPythonLauncherApp(config: Config.defaults));
    expect(find.text('AP Python Launcher'), findsOneWidget);
  });
}
