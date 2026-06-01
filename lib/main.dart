import 'package:ap_python_launcher_app/launcher_screen.dart'
    show LauncherScreen;
import 'package:bison_design_system/bison_design_system.dart'
    show BisonThemeData;
import 'package:flutter/material.dart';

/// Entry point for the AP Python Launcher application.
void main() {
  runApp(const ApPythonLauncherApp());
}

/// The root widget of the AP Python Launcher application.
class ApPythonLauncherApp extends StatelessWidget {
  /// Creates an [ApPythonLauncherApp].
  const ApPythonLauncherApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'AP Python Launcher',
      theme: BisonThemeData.dark(),
      darkTheme: BisonThemeData.dark(),
      home: const LauncherScreen(),
    );
  }
}
