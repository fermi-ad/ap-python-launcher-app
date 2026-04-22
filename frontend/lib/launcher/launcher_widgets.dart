import 'package:bison_design_system/bison_design_system.dart'
    show BisonButton, BisonContext;
import 'package:flutter/material.dart';
import 'package:frontend/api_service.dart' show AppInfo;
import 'package:frontend/connect.dart' show openInNewTab;
import 'package:frontend/launcher/launcher_models.dart'
    show RowState, RowStateKind;

class StatusText extends StatelessWidget {
  const StatusText({required this.text, super.key});
  final String text;

  static final RegExp _urlRegex = RegExp(r'https?://\S+');

  @override
  Widget build(BuildContext context) {
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

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
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

class Panel extends StatelessWidget {
  const Panel({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
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

class AppsTable extends StatelessWidget {
  const AppsTable({
    required this.apps,
    required this.rowStateFor,
    required this.onLaunch,
    required this.onEnd,
    super.key,
  });
  final List<AppInfo> apps;
  final RowState Function(String repo, String tag) rowStateFor;
  final Future<void> Function(String repo, String tag) onLaunch;
  final Future<void> Function(String launchId, String repo, String tag) onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;

        if (isNarrow) {
          return Column(
            children: apps.map((a) {
              final tag = a.tag ?? 'latest';
              final state = rowStateFor(a.repo, tag);
              final repoDisplay = a.repo.replaceFirst(
                RegExp('^ap-python/'),
                '',
              );

              final statusText = switch (state.kind) {
                RowStateKind.idle => '—',
                RowStateKind.pending => 'Pending',
                RowStateKind.running => 'Running',
                RowStateKind.ready => 'Ready',
                RowStateKind.ending => 'Ending...',
              };

              Widget action;
              if (state.kind == RowStateKind.ready &&
                  state.connectUrl != null) {
                action = Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ConnectButton(url: state.connectUrl!),
                    EndButton(
                      onPressed: state.launchId == null
                          ? null
                          : () => onEnd(state.launchId!, a.repo, tag),
                    ),
                  ],
                );
              } else if (state.kind == RowStateKind.pending ||
                  state.kind == RowStateKind.running ||
                  state.kind == RowStateKind.ending) {
                action = EndButton(
                  onPressed:
                      (state.kind == RowStateKind.ending ||
                          state.launchId == null)
                      ? null
                      : () => onEnd(state.launchId!, a.repo, tag),
                );
              } else {
                action = LaunchButton(onPressed: () => onLaunch(a.repo, tag));
              }

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
                      'Status: $statusText',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: action),
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
                DataColumn(
                  label: SizedBox(width: 120, child: Text('Status')),
                ),
                DataColumn(
                  label: SizedBox(
                    width: actionsWidth,
                    child: Text('Actions'),
                  ),
                ),
              ],
              rows: apps.map((a) {
                final tag = a.tag ?? 'latest';
                final state = rowStateFor(a.repo, tag);
                final repoDisplay = a.repo.replaceFirst(
                  RegExp('^ap-python/'),
                  '',
                );

                final statusText = switch (state.kind) {
                  RowStateKind.idle => '—',
                  RowStateKind.pending => 'Pending',
                  RowStateKind.running => 'Running',
                  RowStateKind.ready => 'Ready',
                  RowStateKind.ending => 'Ending...',
                };

                Widget action;
                if (state.kind == RowStateKind.ready &&
                    state.connectUrl != null) {
                  action = SizedBox(
                    width: actionsWidth,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ConnectButton(url: state.connectUrl!),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: EndButton(
                            onPressed: state.launchId == null
                                ? null
                                : () => onEnd(state.launchId!, a.repo, tag),
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (state.kind == RowStateKind.pending ||
                    state.kind == RowStateKind.running ||
                    state.kind == RowStateKind.ending) {
                  action = SizedBox(
                    width: actionsWidth,
                    child: EndButton(
                      onPressed:
                          (state.kind == RowStateKind.ending ||
                              state.launchId == null)
                          ? null
                          : () => onEnd(state.launchId!, a.repo, tag),
                    ),
                  );
                } else {
                  action = SizedBox(
                    width: actionsWidth,
                    child: LaunchButton(onPressed: () => onLaunch(a.repo, tag)),
                  );
                }

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
                    DataCell(SizedBox(width: 120, child: Text(statusText))),
                    DataCell(SizedBox(width: actionsWidth, child: action)),
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

class LaunchButton extends StatelessWidget {
  const LaunchButton({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BisonButton.filled(
      buttonLabel: 'Launch',
      icon: const Icon(Icons.add),
      onPressed: onPressed,
    );
  }
}

class EndButton extends StatelessWidget {
  const EndButton({required this.onPressed, super.key});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return BisonButton.destructive(
      buttonLabel: 'End',
      icon: const Icon(Icons.delete_outline),
      onPressed: onPressed,
    );
  }
}

class ConnectButton extends StatelessWidget {
  const ConnectButton({required this.url, super.key});
  final String url;

  @override
  Widget build(BuildContext context) {
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

class LaunchStatusPanel extends StatelessWidget {
  const LaunchStatusPanel({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final monoStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'RobotoMono',
          fontFamilyFallback: const [
            'ui-monospace',
            'SFMono-Regular',
            'Menlo',
            'Monaco',
            'Consolas',
            'Liberation Mono',
            'Courier New',
            'monospace',
          ],
          height: 1.25,
        ) ??
        const TextStyle(
          fontFamily: 'RobotoMono',
          fontFamilyFallback: [
            'ui-monospace',
            'SFMono-Regular',
            'Menlo',
            'Monaco',
            'Consolas',
            'Liberation Mono',
            'Courier New',
            'monospace',
          ],
          height: 1.25,
        );

    final tokens = context.bison;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.theme.borderPlain),
      ),
      child: SelectableText(text, style: monoStyle),
    );
  }
}
