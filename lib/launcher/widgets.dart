import 'package:ap_python_launcher_app/api_service.dart' show AppInfo;
import 'package:ap_python_launcher_app/connect/connect.dart' show openInNewTab;
import 'package:ap_python_launcher_app/launcher/models.dart'
    show RowState, RowStateKind;
import 'package:bison_design_system/bison_design_system.dart'
    show BisonButton, BisonContext;
import 'package:flutter/material.dart';

/// Displays a status message, rendering any embedded URL as a tappable link.
class StatusText extends StatelessWidget {
  /// Creates a [StatusText] widget with the given [text].
  const StatusText({required this.text, super.key});

  /// The status message to display.
  final String text;

  static final RegExp _urlRegex = RegExp(r'https?://\S+');

  @override
  Widget build(final BuildContext context) {
    final match = _urlRegex.firstMatch(text);
    final url = match?.group(0);

    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(
        context,
      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
    );

    if (url == null) {
      return Text(text, style: baseStyle);
    }

    final before = text.substring(0, match!.start);
    final after = text.substring(match.end);

    final linkColor = Theme.of(context).colorScheme.primary;

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              onTap: () => openInNewTab(url),
              child: Text(
                url,
                style: baseStyle?.copyWith(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}

/// Displays the application title and subtitle header.
class Header extends StatelessWidget {
  /// Creates a [Header] widget.
  const Header({super.key});

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AP Python Launcher',
          style: Theme.of(context).textTheme.displayLarge,
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

/// A card-style container that wraps its [child] with a border and padding.
class Panel extends StatelessWidget {
  /// Creates a [Panel] with the given [child].
  const Panel({required this.child, super.key});

  /// The widget to display inside the panel.
  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final tokens = context.bison;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.corners.cornerMedium),
        side: BorderSide(color: tokens.theme.borderPlain),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.standardSpacing),
        child: child,
      ),
    );
  }
}

/// Displays a table (or card list on narrow screens) of launchable apps.
class AppsTable extends StatelessWidget {
  /// Creates an [AppsTable].
  const AppsTable({
    required this.apps,
    required this.rowStateFor,
    required this.onLaunch,
    required this.onEnd,
    super.key,
  });

  /// The list of apps to display.
  final List<AppInfo> apps;

  /// Returns the current [RowState] for a given repo and tag.
  final RowState Function(String repo, String tag) rowStateFor;

  /// Called when the user requests a launch for a repo at a given tag.
  final Future<void> Function(String repo, String tag) onLaunch;

  /// Called when the user requests to end the job identified by a launch ID.
  final Future<void> Function(String launchId, String repo, String tag) onEnd;

  static String _statusText(final RowState state) {
    final override = state.statusOverride;
    if (override != null && override.isNotEmpty) return override;

    return switch (state.kind) {
      RowStateKind.idle => '—',
      RowStateKind.checking => 'Checking...',
      RowStateKind.pending => 'Pending',
      RowStateKind.running => 'Running',
      RowStateKind.ready => 'Ready',
      RowStateKind.ending => 'Ending...',
      RowStateKind.statusUnavailable => 'Unavailable',
    };
  }

  Widget _buildAction(
    final RowState state,
    final String repo,
    final String tag, {
    final double? width,
  }) {
    final endButton = EndButton(
      onPressed: (state.kind == RowStateKind.ending || state.launchId == null)
          ? null
          : () => onEnd(state.launchId!, repo, tag),
    );

    Widget inner;
    if (state.kind == RowStateKind.ready && state.connectUrl != null) {
      inner = width != null
          ? Row(
              children: [
                Expanded(flex: 2, child: ConnectButton(url: state.connectUrl!)),
                const SizedBox(width: 16),
                Expanded(child: endButton),
              ],
            )
          : Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ConnectButton(url: state.connectUrl!),
                endButton,
              ],
            );
    } else if (state.kind == RowStateKind.checking ||
        state.kind == RowStateKind.pending ||
        state.kind == RowStateKind.running ||
        state.kind == RowStateKind.ending) {
      inner = endButton;
    } else {
      inner = LaunchButton(onPressed: () => onLaunch(repo, tag));
    }

    return width != null ? SizedBox(width: width, child: inner) : inner;
  }

  @override
  Widget build(final BuildContext context) {
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final isNarrow = constraints.maxWidth < 720;

        if (isNarrow) {
          return Column(
            children: apps.map((final a) {
              final tag = a.tag ?? 'latest';
              final state = rowStateFor(a.repo, tag);
              final repoDisplay = a.repo.replaceFirst(
                RegExp('^ap-python/'),
                '',
              );

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      repoDisplay,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Status: ${_statusText(state)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildAction(state, a.repo, tag),
                    ),
                    const Divider(height: 24),
                  ],
                ),
              );
            }).toList(),
          );
        }

        const double actionsWidth = 260;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(
                  label: SizedBox(width: 300, child: Text('Repository')),
                ),
                DataColumn(label: SizedBox(width: 120, child: Text('Status'))),
                DataColumn(
                  label: SizedBox(width: actionsWidth, child: Text('Actions')),
                ),
              ],
              rows: apps.map((final a) {
                final tag = a.tag ?? 'latest';
                final state = rowStateFor(a.repo, tag);
                final repoDisplay = a.repo.replaceFirst(
                  RegExp('^ap-python/'),
                  '',
                );

                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 300,
                        child: Text(
                          repoDisplay,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(width: 120, child: Text(_statusText(state))),
                    ),
                    DataCell(
                      _buildAction(state, a.repo, tag, width: actionsWidth),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

/// A button that triggers a launch action.
class LaunchButton extends StatelessWidget {
  /// Creates a [LaunchButton] with the given [onPressed] callback.
  const LaunchButton({required this.onPressed, super.key});

  /// Called when the button is tapped.
  final VoidCallback onPressed;

  @override
  Widget build(final BuildContext context) {
    return BisonButton.filled(
      buttonLabel: 'Launch',
      icon: const Icon(Icons.add),
      onPressed: onPressed,
    );
  }
}

/// A destructive button that triggers an end-job action.
class EndButton extends StatelessWidget {
  /// Creates an [EndButton] with the given [onPressed] callback.
  ///
  /// Pass `null` for [onPressed] to disable the button.
  const EndButton({required this.onPressed, super.key});

  /// Called when the button is tapped, or `null` to disable the button.
  final VoidCallback? onPressed;

  @override
  Widget build(final BuildContext context) {
    return BisonButton.destructive(
      buttonLabel: 'End',
      icon: const Icon(Icons.delete_outline),
      onPressed: onPressed,
    );
  }
}

/// A button that opens the app's connect [url] in a new browser tab.
class ConnectButton extends StatelessWidget {
  /// Creates a [ConnectButton] for the given [url].
  const ConnectButton({required this.url, super.key});

  /// The URL to open when the button is tapped.
  final String url;

  @override
  Widget build(final BuildContext context) {
    final success = Theme.of(context).colorScheme.tertiary;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: success),
      ),
      child: BisonButton.filled(
        buttonLabel: 'Connect',
        icon: const Icon(Icons.open_in_new),
        onPressed: () => openInNewTab(url),
      ),
    );
  }
}

/// Displays a panel showing the raw JSON of the latest launch status.
class LaunchStatusPanel extends StatelessWidget {
  /// Creates a [LaunchStatusPanel] with the given [text].
  const LaunchStatusPanel({required this.text, super.key});

  /// The text to display, typically pretty-printed JSON.
  final String text;

  @override
  Widget build(final BuildContext context) {
    final tokens = context.bison;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.theme.borderPlain),
      ),
      child: SelectableText(text, style: const TextStyle(color: Colors.white)),
    );
  }
}
