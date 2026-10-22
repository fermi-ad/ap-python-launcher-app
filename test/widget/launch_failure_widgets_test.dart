import 'package:ap_python_launcher_app/api_service.dart' show AppInfo;
import 'package:ap_python_launcher_app/launcher/models.dart'
    show RowState, RowStateKind;
import 'package:ap_python_launcher_app/launcher/widgets.dart'
    show AppsTable, LaunchStatusPanel;
import 'package:flutter/material.dart';
import 'package:flutter_controls_core/flutter_controls_core.dart'
    show BisonThemeData;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed row shows Failed and allows launching again', (
    final tester,
  ) async {
    var launches = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BisonThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: AppsTable(
              apps: [
                AppInfo(
                  repo: 'ap-python/foo',
                  tag: 'latest',
                  allTags: const [],
                ),
              ],
              rowStateFor: (final repo, final tag) => const RowState(
                kind: RowStateKind.failed,
              ),
              onLaunch: (final repo, final tag) async {
                launches++;
              },
              onEnd: (final id, final repo, final tag) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Status: Failed'), findsOneWidget);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('End'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Launch'));
    expect(launches, 1);
  });

  testWidgets('status panel displays failure JSON as selectable text', (
    final tester,
  ) async {
    const json = '{"error":"Storage collision. Launch again."}';
    await tester.pumpWidget(
      MaterialApp(
        theme: BisonThemeData.dark(),
        home: const Scaffold(body: LaunchStatusPanel(text: json)),
      ),
    );

    expect(find.text(json), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
