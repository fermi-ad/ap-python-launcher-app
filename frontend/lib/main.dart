import 'package:bison_design_system/bison_design_system.dart'
    show BisonThemeData;
import 'package:flutter/material.dart';
import 'package:frontend/launcher_screen.dart' show LauncherScreen;

void main() {
  runApp(const ApPythonLauncherApp());
}

class ApPythonLauncherApp extends StatelessWidget {
  const ApPythonLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AP Python Launcher',
      theme: BisonThemeData.dark(),
      darkTheme: BisonThemeData.dark(),
      home: const LauncherScreen(),
    );
  }
}
