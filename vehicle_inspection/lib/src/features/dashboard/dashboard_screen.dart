import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../domain/entities/inspection_summary.dart';
import '../auth/auth_controller.dart';
import '../history/widgets/inspection_row.dart';
import '../sync/sync_banner.dart';

/// Landing screen: who is signed in, what is outstanding, and the two actions
/// that matter — start an inspection, or open the ones already on the device.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final evaluator = ref.watch(currentEvaluatorProvider);
    final stats = ref.watch(dashboardStatsProvider).value ?? DashboardStats.empty;
    final summaries = ref.watch(inspectionSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                evaluator?.initials ?? '?',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Evaluator',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    evaluator?.name ?? 'Signed out',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncBanner(showWhenIdle: true),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref
                    .read(syncEngineProvider)
                    .requestSync(reason: 'pull to refresh');
                ref.invalidate(inspectionSummariesProvider);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _StatsRow(stats: stats),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushNamed(AppRoutes.newInspection),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Inspection'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.history),
                    icon: const Icon(Icons.list_alt_rounded),
                    label: const Text('My Inspections'),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if ((summaries.value?.length ?? 0) > 5)
                        TextButton(
                          onPressed: () => Navigator.of(context)
                              .pushNamed(AppRoutes.history),
                          child: const Text('See all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._buildRecent(context, summaries),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRecent(
    BuildContext context,
    AsyncValue<List<InspectionSummary>> summaries,
  ) {
    return summaries.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, _) => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Could not load inspections: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      data: (items) {
        if (items.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 42,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No inspections yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ];
        }
        return [
          for (final summary in items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InspectionRow(summary: summary),
            ),
        ];
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        // Reassurance matters here: an evaluator with unsynced work needs to
        // know signing out is not going to discard it.
        content: const Text(
          'Inspections saved on this device are kept and will sync the next '
          'time you sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final statusColors = context.statusColors;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Completed',
            value: stats.completedCount,
            icon: Icons.task_alt_rounded,
            color: statusColors.pass,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Pending sync',
            value: stats.pendingSyncCount,
            icon: Icons.cloud_queue_rounded,
            color: stats.failedSyncCount > 0
                ? statusColors.fail
                : statusColors.minorIssue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Drafts',
            value: stats.draftCount,
            icon: Icons.edit_note_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
