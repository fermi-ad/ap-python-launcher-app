import 'package:ap_python_launcher_app/api_service.dart' as api;
import 'package:ap_python_launcher_app/launcher/models.dart' as models;
import 'package:ap_python_launcher_app/launcher/widgets.dart'
    show AppsTable, StatusText;
import 'package:flutter/material.dart';
import 'package:flutter_controls_core/flutter_controls_core.dart'
    show BisonThemeData;
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

  group('AppsTable', () {
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
                onEnd: (final launchId, final repo, final tag) async {},
              ),
            ),
          ),
        ),
      );

      final endButton = tester.widget<Widget>(find.text('End'));
      expect(endButton, isNotNull);
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
      expect(find.textContaining('Status:'), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
    });
  });
}
