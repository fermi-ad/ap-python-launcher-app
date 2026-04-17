import 'package:flutter/material.dart';

import 'launcher_screen.dart';

void main() {
  runApp(const ApPythonLauncherApp());
}

class ApPythonLauncherApp extends StatelessWidget {
  const ApPythonLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B1220);
    const panel = Color(0xFF111A2E);
    const border = Color(0xFF23324F);
    const text = Color(0xFFE6EDF3);
    const link = Color(0xFF60A5FA);

    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF2563EB),
        secondary: link,
        surface: panel,
        onSurface: text,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w600),
        dividerThickness: 1,
      ),
      cardTheme: const CardThemeData(
        color: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );

    return MaterialApp(
      title: 'AP Python Launcher',
      theme: theme,
      home: const LauncherScreen(),
    );
  }
}
