import 'package:ap_python_launcher_app/api_service.dart' show AppInfo;
import 'package:ap_python_launcher_app/launcher/models.dart'
    show RowState, RowStateKind;
import 'package:ap_python_launcher_app/launcher/widgets.dart'
    show AppsTable, LaunchErrorBanner;
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

  testWidgets('one persistent banner displays the latest error', (
    final tester,
  ) async {
    Widget build(final String? error) => MaterialApp(
      theme: BisonThemeData.dark(),
      home: Scaffold(
        body: Column(
          children: [if (error != null) LaunchErrorBanner(message: error)],
        ),
      ),
    );
    await tester.pumpWidget(
      build('ap-python/foo: Storage collision. Launch again.'),
    );
    await tester.pump(const Duration(minutes: 1));
    expect(find.byType(LaunchErrorBanner), findsOneWidget);
    expect(
      find.text('ap-python/foo: Storage collision. Launch again.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsNothing);
    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(LaunchErrorBanner),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.liveRegion, isTrue);
    await tester.pumpWidget(
      build('ap-python/bar: Storage permissions unavailable.'),
    );
    expect(find.byType(LaunchErrorBanner), findsOneWidget);
    expect(
      find.text('ap-python/foo: Storage collision. Launch again.'),
      findsNothing,
    );
    expect(
      find.text('ap-python/bar: Storage permissions unavailable.'),
      findsOneWidget,
    );
    await tester.pumpWidget(build(null));
    expect(find.byType(LaunchErrorBanner), findsNothing);
  });
}
