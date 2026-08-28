import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/state_views.dart';
import '../../data/remote/mock/network_simulator.dart';
import '../sync/sync_banner.dart';

/// Preferences plus the switches that make offline behaviour testable.
///
/// The "Network simulation" section exists so offline sync can be reviewed
/// without putting the phone into airplane mode part-way through a checklist.
/// It drives the same [NetworkSimulator] the connectivity monitor observes, so
/// flipping it offline is indistinguishable from losing signal — the banner,
/// the queue and the retry logic all react exactly as they would in the field.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final simulator = ref.watch(networkSimulatorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final syncState = ref.watch(syncStateProvider).value;
    final template = ref.watch(activeTemplateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SyncBanner(showWhenIdle: true),

          _SectionHeader(title: 'Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(themeModeProvider.notifier).state = mode;
              }
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('Follow system'),
                  dense: true,
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                  dense: true,
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                  dense: true,
                ),
              ],
            ),
          ),

          const Divider(height: 24),
          _SectionHeader(
            title: 'Network simulation',
            subtitle: 'For testing offline behaviour without airplane mode.',
          ),
          ValueListenableBuilder<NetworkConditions>(
            valueListenable: simulator,
            builder: (context, conditions, _) => Column(
              children: [
                SwitchListTile(
                  value: conditions.offline,
                  onChanged: (value) {
                    simulator.setOffline(value);
                    AppMessenger.showInfo(
                      context,
                      value
                          ? 'Simulating offline. Submissions will queue.'
                          : 'Back online. Queued work will sync.',
                    );
                  },
                  secondary: Icon(
                    conditions.offline
                        ? Icons.wifi_off_rounded
                        : Icons.wifi_rounded,
                  ),
                  title: const Text('Simulate offline'),
                  subtitle: const Text(
                    'Requests fail immediately, as with no signal',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.error_outline_rounded),
                  title: const Text('Server error rate'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(conditions.failureRate * 100).round()}% of '
                        'requests return a 503',
                      ),
                      Slider(
                        value: conditions.failureRate,
                        max: 1,
                        divisions: 10,
                        label: '${(conditions.failureRate * 100).round()}%',
                        onChanged: simulator.setFailureRate,
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Response latency'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${conditions.latency.inMilliseconds} ms'),
                      Slider(
                        value: conditions.latency.inMilliseconds
                            .toDouble()
                            .clamp(0, 4000),
                        max: 4000,
                        divisions: 8,
                        label: '${conditions.latency.inMilliseconds} ms',
                        onChanged: (value) => simulator.setLatency(
                          Duration(milliseconds: value.round()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 24),
          _SectionHeader(title: 'Sync'),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Pending items'),
            subtitle: Text(
              syncState == null
                  ? 'Starting up...'
                  : '${syncState.pendingTasks} queued  -  ${syncState.message}',
            ),
            trailing: FilledButton.tonal(
              onPressed: () => ref
                  .read(syncEngineProvider)
                  .requestSync(reason: 'settings screen'),
              child: const Text('Sync now'),
            ),
          ),

          const Divider(height: 24),
          _SectionHeader(title: 'Checklist template'),
          template.when(
            loading: () => const ListTile(
              leading: Icon(Icons.checklist_rounded),
              title: Text('Loading...'),
            ),
            error: (error, _) => ListTile(
              leading: Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
              ),
              title: const Text('Template unavailable'),
              subtitle: Text('$error'),
            ),
            data: (value) => ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: Text(value.name),
              subtitle: Text(
                'Version ${value.version}  -  ${value.categories.length} '
                'categories  -  ${value.totalPointCount} points '
                '(${value.requiredPointCount} required)',
              ),
              // Pulls whatever the admin dashboard has published since the last
              // sync. Safe to tap offline: a failed refresh keeps the cached
              // template rather than surfacing an error.
              trailing: FilledButton.tonal(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final changed =
                        await ref.refresh(templateRefreshProvider.future);
                    if (!context.mounted) return;
                    AppMessenger.showSuccess(
                      context,
                      changed
                          ? 'Updated to a newer checklist'
                          : 'Already on the latest checklist',
                    );
                  } catch (error) {
                    messenger.hideCurrentSnackBar();
                    if (context.mounted) AppMessenger.showError(context, error);
                  }
                },
                child: const Text('Check for updates'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Vehicle Inspection  -  v1.0.0',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
