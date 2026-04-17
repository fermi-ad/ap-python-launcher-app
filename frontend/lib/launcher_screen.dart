import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:bison_design_system/bison_design_system.dart';

import 'api_service.dart';
import 'connect.dart';
import 'job_store.dart';

enum RowStateKind { idle, pending, running, ready, ending }

class RowState {
  final RowStateKind kind;
  final String? launchId;
  final String? connectUrl;

  const RowState({required this.kind, this.launchId, this.connectUrl});

  RowState copyWith({
    RowStateKind? kind,
    String? launchId,
    String? connectUrl,
  }) {
    return RowState(
      kind: kind ?? this.kind,
      launchId: launchId ?? this.launchId,
      connectUrl: connectUrl ?? this.connectUrl,
    );
  }
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  final ApiService _api = ApiService();
  final JobStore _jobs = JobStore();

  List<AppInfo> _apps = const [];
  String _statusText = 'Ready';
  String _launchJson = 'No new launches';

  // key: "$repo:$tag"
  final Map<String, RowState> _rowStates = {};
  final Map<String, Timer> _pollers = {};

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    for (final t in _pollers.values) {
      t.cancel();
    }
    _pollers.clear();
    super.dispose();
  }

  String _key(String repo, String tag) => '$repo:$tag';

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
  }

  void _setLaunchJson(Object obj) {
    if (!mounted) return;
    setState(
      () => _launchJson = const JsonEncoder.withIndent('  ').convert(obj),
    );
  }

  void _setRowState(String repo, String tag, RowState state) {
    if (!mounted) return;
    setState(() {
      _rowStates[_key(repo, tag)] = state;
    });
  }

  RowState _getRowState(String repo, String tag) {
    return _rowStates[_key(repo, tag)] ??
        const RowState(kind: RowStateKind.idle);
  }

  Future<void> _refresh() async {
    _setStatus('Refreshing...');
    try {
      final apps = await _api.getApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        // Ensure every row has a state entry.
        for (final a in apps) {
          final tag = a.tag ?? 'latest';
          _rowStates.putIfAbsent(
            _key(a.repo, tag),
            () => const RowState(kind: RowStateKind.idle),
          );
        }
      });

      final currentTags = <String, String>{
        for (final a in apps) a.repo: (a.tag ?? 'latest'),
      };
      await _restoreJobs(currentTags);

      _setStatus('Loaded ${apps.length} app(s)');
    } catch (e) {
      _setStatus('Refresh failed');
      _setLaunchJson({'error': e.toString()});
    }
  }

  Future<void> _restoreJobs(Map<String, String> currentTags) async {
    final saved = await _jobs.loadJobs();

    for (final job in saved) {
      // Drop stale jobs if tag no longer matches current resolved tag.
      if (currentTags.containsKey(job.repo) &&
          currentTags[job.repo] != job.tag) {
        await _jobs.removeJob(job.launchId);
        continue;
      }

      LaunchStatus st;
      try {
        st = await _api.getLaunchStatus(job.launchId);
      } catch (_) {
        await _jobs.removeJob(job.launchId);
        continue;
      }

      final urls = st.access.urls;
      final accessStatus = st.access.status;

      if (urls.isNotEmpty && accessStatus == 'Ready') {
        _setRowState(
          job.repo,
          job.tag,
          RowState(
            kind: RowStateKind.ready,
            launchId: job.launchId,
            connectUrl: urls.first,
          ),
        );
      } else if (st.status == 'Succeeded' || st.status == 'Failed') {
        await _jobs.removeJob(job.launchId);
        _setRowState(
          job.repo,
          job.tag,
          const RowState(kind: RowStateKind.idle),
        );
      } else {
        _setRowState(
          job.repo,
          job.tag,
          RowState(kind: RowStateKind.running, launchId: job.launchId),
        );
        _startPolling(job.launchId, job.repo, job.tag);
      }
    }
  }

  Future<void> _launch(String repo, String tag) async {
    _setStatus('Launching $repo...');
    try {
      final resp = await _api.postLaunch(repo);
      _setLaunchJson(resp.raw);
      _setStatus('Launch requested; waiting for LoadBalancer...');

      final launchId = resp.launchId;
      final resolvedTag = resp.tag ?? tag;
      if (launchId.isEmpty) return;

      await _jobs.saveJob(launchId, repo, resolvedTag);
      _setRowState(
        repo,
        resolvedTag,
        RowState(kind: RowStateKind.pending, launchId: launchId),
      );
      _startPolling(launchId, repo, resolvedTag);
    } catch (e) {
      _setLaunchJson({'error': e.toString()});
      _setStatus('Launch failed');
    }
  }

  Future<void> _end(String launchId, String repo, String tag) async {
    _setStatus('Ending job...');
    _setRowState(
      repo,
      tag,
      RowState(kind: RowStateKind.ending, launchId: launchId),
    );

    try {
      await _api.deleteLaunch(launchId);
    } catch (e) {
      _setStatus('Failed to end job: $e');
      _setRowState(
        repo,
        tag,
        RowState(kind: RowStateKind.running, launchId: launchId),
      );
      return;
    }

    // Poll until ended (or timeout)
    final ended = await _pollUntilEnded(
      launchId,
      timeout: const Duration(seconds: 30),
      poll: const Duration(seconds: 2),
      onStatus: (st) => _setLaunchJson(st.raw),
    );

    await _jobs.removeJob(launchId);
    _stopPolling(launchId);

    if (ended) {
      _setStatus('Job ended');
    } else {
      _setStatus('End requested; still terminating...');
    }

    _setRowState(repo, tag, const RowState(kind: RowStateKind.idle));
  }

  void _startPolling(String launchId, String repo, String tag) {
    _stopPolling(launchId);

    _pollers[launchId] = Timer.periodic(const Duration(seconds: 2), (_) async {
      // If job no longer saved, stop.
      final saved = await _jobs.loadJobs();
      if (!saved.any((j) => j.launchId == launchId)) {
        _stopPolling(launchId);
        return;
      }

      LaunchStatus st;
      try {
        st = await _api.getLaunchStatus(launchId);
      } catch (_) {
        await _jobs.removeJob(launchId);
        _setStatus('Job no longer found; cleared from saved jobs');
        _setRowState(repo, tag, const RowState(kind: RowStateKind.idle));
        _stopPolling(launchId);
        return;
      }

      _setLaunchJson(st.raw);

      final urls = st.access.urls;
      final accessStatus = st.access.status;

      if (urls.isNotEmpty && accessStatus == 'Ready') {
        _setStatus('App is reachable: ${urls.join(", ")}');
        _setRowState(
          repo,
          tag,
          RowState(
            kind: RowStateKind.ready,
            launchId: launchId,
            connectUrl: urls.first,
          ),
        );
        _stopPolling(launchId);
        return;
      }

      if (st.status == 'Succeeded' || st.status == 'Failed') {
        _setStatus('Job ${st.status}; access cleaned up');
        await _jobs.removeJob(launchId);
        _setRowState(repo, tag, const RowState(kind: RowStateKind.idle));
        _stopPolling(launchId);
        return;
      }

      // Pending vs running
      final pending = _isPendingStatus(st);
      _setRowState(
        repo,
        tag,
        RowState(
          kind: pending ? RowStateKind.pending : RowStateKind.running,
          launchId: launchId,
        ),
      );

      _setStatus('Waiting for LoadBalancer...');
    });
  }

  void _stopPolling(String launchId) {
    _pollers.remove(launchId)?.cancel();
  }

  bool _isPendingStatus(LaunchStatus st) {
    final status = st.status.toLowerCase();
    final accessStatus = st.access.status.toLowerCase();
    return status == 'pending' || accessStatus == 'pending';
  }

  Future<bool> _pollUntilEnded(
    String launchId, {
    required Duration timeout,
    required Duration poll,
    required void Function(LaunchStatus st) onStatus,
  }) async {
    final start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      try {
        final st = await _api.getLaunchStatus(launchId);
        onStatus(st);
        if (st.status == 'NotFound' ||
            st.status == 'Succeeded' ||
            st.status == 'Failed') {
          return true;
        }
      } catch (_) {
        return true;
      }

      await Future<void>.delayed(poll);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 16),
                _Panel(
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
                            child: Text(
                              _statusText,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.85),
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _AppsTable(
                        apps: _apps,
                        rowStateFor: _getRowState,
                        onLaunch: _launch,
                        onEnd: _end,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Launch status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _LaunchStatusPanel(text: _launchJson),
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AP Python Launcher',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Select an app to launch.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _AppsTable extends StatelessWidget {
  final List<AppInfo> apps;
  final RowState Function(String repo, String tag) rowStateFor;
  final void Function(String repo, String tag) onLaunch;
  final void Function(String launchId, String repo, String tag) onEnd;

  const _AppsTable({
    required this.apps,
    required this.rowStateFor,
    required this.onLaunch,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Repository')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Action')),
        ],
        rows: apps.map((a) {
          final tag = a.tag ?? 'latest';
          final state = rowStateFor(a.repo, tag);
          final repoDisplay = a.repo.replaceFirst(RegExp(r'^ap-python/'), '');

          final statusText = switch (state.kind) {
            RowStateKind.idle => '—',
            RowStateKind.pending => 'Pending',
            RowStateKind.running => 'Running',
            RowStateKind.ready => 'Ready',
            RowStateKind.ending => 'Ending...',
          };

          Widget action;
          if (state.kind == RowStateKind.ready && state.connectUrl != null) {
            action = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ConnectButton(url: state.connectUrl!),
                const SizedBox(width: 16),
                _EndButton(
                  onPressed: state.launchId == null
                      ? null
                      : () => onEnd(state.launchId!, a.repo, tag),
                ),
              ],
            );
          } else if (state.kind == RowStateKind.pending ||
              state.kind == RowStateKind.running ||
              state.kind == RowStateKind.ending) {
            action = _EndButton(
              onPressed:
                  (state.kind == RowStateKind.ending || state.launchId == null)
                  ? null
                  : () => onEnd(state.launchId!, a.repo, tag),
            );
          } else {
            action = _LaunchButton(onPressed: () => onLaunch(a.repo, tag));
          }

          return DataRow(
            cells: [
              DataCell(Text(repoDisplay)),
              DataCell(Text(statusText)),
              DataCell(action),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LaunchButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return BisonButton.filled(buttonLabel: 'Launch', onPressed: onPressed);
  }
}

class _EndButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _EndButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return BisonButton.destructive(buttonLabel: 'End', onPressed: onPressed);
  }
}

class _ConnectButton extends StatelessWidget {
  final String url;

  const _ConnectButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return BisonButton.filled(
      buttonLabel: 'Connect',
      onPressed: () => openInNewTab(url),
    );
  }
}

class _LaunchStatusPanel extends StatelessWidget {
  final String text;

  const _LaunchStatusPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF23324F)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', height: 1.25),
      ),
    );
  }
}
