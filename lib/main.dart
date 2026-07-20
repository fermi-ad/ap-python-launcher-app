import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:ap_python_launcher_app/launcher_page.dart' show LauncherPage;
import 'package:bison_design_system/bison_design_system.dart'
    show BisonThemeData;
import 'package:flutter/material.dart';

/// Entry point for the AP Python Launcher application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await Config.load();
  runApp(ApPythonLauncherApp(config: config));
}

/// The root widget of the AP Python Launcher application.
class ApPythonLauncherApp extends StatelessWidget {
  /// Creates an [ApPythonLauncherApp].
  const ApPythonLauncherApp({required this.config, super.key});

  /// Runtime configuration loaded in [main].
  final Config config;

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'AP Python Launcher',
      theme: BisonThemeData.dark(),
      darkTheme: BisonThemeData.dark(),
      home: LauncherPage(config: config),
    );
  }
}
