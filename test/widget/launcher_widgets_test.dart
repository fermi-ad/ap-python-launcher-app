import 'package:ap_python_launcher_app/api_service.dart' as api;
import 'package:ap_python_launcher_app/launcher/models.dart' as models;
import 'package:ap_python_launcher_app/launcher/widgets.dart'
    show AppsTable, LaunchStatusPanel, StatusText;
import 'package:flutter/material.dart';
import 'package:flutter_controls_core/flutter_controls_core.dart'
    show BisonButton, BisonThemeData;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusText', () {
    testWidgets('renders plain text when no url present', (final tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusText(text: 'Ready')),
        ),
      );

      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets('renders url as tappable text when url present', (
      final tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusText(text: 'App is reachable: http://host:80/'),
          ),
        ),
      );

      expect(find.text('http://host:80/'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('LaunchStatusPanel', () {
    testWidgets('displays failure JSON as selectable text', (
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
  });

  group('AppsTable', () {
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
                  api.AppInfo(
                    repo: 'ap-python/foo',
                    tag: 'latest',
                    allTags: const [],
                  ),
                ],
                rowStateFor: (final repo, final tag) => const models.RowState(
                  kind: models.RowStateKind.failed,
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

    testWidgets('renders one row per app (wide layout)', (final tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BisonThemeData.dark(),
          darkTheme: BisonThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: AppsTable(
                apps: [
                  api.AppInfo(
                    repo: 'ap-python/foo',
                    tag: 'latest',
                    tagTimestamp: '2026-09-15T16:00:00Z',
                    allTags: const [],
                  ),
                  api.AppInfo(
                    repo: 'ap-python/bar',
                    tag: 'v1',
                    allTags: const [],
                  ),
                ],
                rowStateFor: (final repo, final tag) =>
                    const models.RowState(kind: models.RowStateKind.idle),
                onLaunch: (final repo, final tag) async {},
                onEnd: (final launchId, final repo, final tag) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('foo'), findsOneWidget);
      expect(find.text('bar'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);
      expect(find.textContaining('Sep'), findsOneWidget);
      expect(find.byType(Tooltip), findsNWidgets(3));
      expect(find.text('Launch'), findsNWidgets(2));
    });

    testWidgets('shows Connect + End when row is ready', (final tester) async {
      models.RowState stateFor(final String repo, final String tag) {
        return const models.RowState(
          kind: models.RowStateKind.ready,
          launchId: 'id1',
          connectUrl: 'http://host:80/',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: BisonThemeData.dark(),
          darkTheme: BisonThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
                child: AppsTable(
                  apps: [
                    api.AppInfo(
                      repo: 'ap-python/foo',
                      tag: 'latest',
                      allTags: const [],
                    ),
                  ],
                  rowStateFor: stateFor,
                  onLaunch: (final repo, final tag) async {},
                  onEnd: (final launchId, final repo, final tag) async {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.text('Launch'), findsNothing);
    });

    testWidgets('shows End disabled when ending', (final tester) async {
      var ends = 0;
      models.RowState stateFor(final String repo, final String tag) {
        return const models.RowState(
          kind: models.RowStateKind.ending,
          launchId: 'id1',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: BisonThemeData.dark(),
          darkTheme: BisonThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: AppsTable(
                apps: [
                  api.AppInfo(
                    repo: 'ap-python/foo',
                    tag: 'latest',
                    allTags: const [],
                  ),
                ],
                rowStateFor: stateFor,
                onLaunch: (final repo, final tag) async {},
                onEnd: (final launchId, final repo, final tag) async {
                  ends++;
                },
              ),
            ),
          ),
        ),
      );

      final endButton = tester.widget<BisonButton>(find.byType(BisonButton));
      expect(endButton.onPressed, isNull);
      await tester.tap(find.text('End'), warnIfMissed: false);
      await tester.pump();
      expect(ends, 0);
    });

    testWidgets('renders narrow layout as cards', (final tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BisonThemeData.dark(),
          darkTheme: BisonThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: SingleChildScrollView(
                child: AppsTable(
                  apps: [
                    api.AppInfo(
                      repo: 'ap-python/foo',
                      tag: 'latest',
                      allTags: const [],
                    ),
                  ],
                  rowStateFor: (final repo, final tag) =>
                      const models.RowState(kind: models.RowStateKind.idle),
                  onLaunch: (final repo, final tag) async {},
                  onEnd: (final launchId, final repo, final tag) async {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DataTable), findsNothing);
      expect(find.text('foo'), findsOneWidget);
      expect(find.text('Updated: —'), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.textContaining('Status:'), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
    });
  });
}
