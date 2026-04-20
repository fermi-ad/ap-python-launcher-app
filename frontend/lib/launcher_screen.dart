import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bison_design_system/bison_design_system.dart';

import 'launcher/launcher_controller.dart';
import 'launcher/launcher_widgets.dart';

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  final LauncherController _controller = LauncherController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.refresh(_notify));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _notify() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refresh() => _controller.refresh(_notify);

  Future<void> _launch(String repo, String tag) =>
      _controller.launch(repo, tag, _notify);

  Future<void> _end(String launchId, String repo, String tag) =>
      _controller.end(launchId, repo, tag, _notify);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Header(),
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          BisonButton.filled(
                            buttonLabel: 'Refresh',
                            onPressed: _refresh,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatusText(text: _controller.statusText),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppsTable(
                        apps: _controller.apps,
                        rowStateFor: _controller.rowStateFor,
                        onLaunch: _launch,
                        onEnd: _end,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Launch status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      LaunchStatusPanel(text: _controller.launchJson),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
