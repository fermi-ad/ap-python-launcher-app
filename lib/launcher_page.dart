import 'dart:async' show Future, unawaited;

import 'package:ap_python_launcher_app/config.dart' show Config;
import 'package:ap_python_launcher_app/launcher/controller.dart'
    show LauncherController;
import 'package:ap_python_launcher_app/launcher/widgets.dart'
    show AppsTable, Header, LaunchStatusPanel, Panel, StatusText;
import 'package:bison_design_system/bison_design_system.dart' show BisonButton;
import 'package:flutter/material.dart';

/// The main screen of the AP Python Launcher application.
class LauncherPage extends StatefulWidget {
  /// Creates a [LauncherPage].
  const LauncherPage({required this.config, super.key});

  /// Runtime configuration passed down from `main`.
  final Config config;

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  late final LauncherController _controller = LauncherController(
    config: widget.config,
  );

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

  Future<void> _launch(final String repo, final String tag) =>
      _controller.launch(repo, tag, _notify);

  Future<void> _end(
    final String launchId,
    final String repo,
    final String tag,
  ) => _controller.end(launchId, repo, tag, _notify);

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: SingleChildScrollView(
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
      ),
    );
  }
}
