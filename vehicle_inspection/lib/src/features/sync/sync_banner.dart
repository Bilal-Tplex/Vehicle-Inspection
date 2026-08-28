import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../sync/sync_state.dart';

/// Persistent strip describing what sync is doing.
///
/// The evaluator's core anxiety offline is "did my work survive?". This answers
/// it continuously — how many records are waiting, whether the device is
/// online, and what the app is doing about it — instead of only speaking up
/// when something fails.
///
/// It hides itself when everything is synced and the device is online, so it
/// costs no screen space in the normal case.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({this.showWhenIdle = false, super.key});

  /// Keeps the banner visible even when there is nothing to report, used on
  /// the dashboard where the reassurance is worth the space.
  final bool showWhenIdle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStateProvider).value ?? const SyncState();
    final theme = Theme.of(context);
    final statusColors = context.statusColors;

    final isQuiet =
        syncState.phase == SyncPhase.idle && !syncState.hasPendingWork;
    if (isQuiet && syncState.isOnline && !showWhenIdle) {
      return const SizedBox.shrink();
    }

    final (color, icon) = switch (syncState.phase) {
      SyncPhase.idle => syncState.isOnline
          ? (statusColors.pass, Icons.cloud_done_outlined)
          : (statusColors.notApplicable, Icons.wifi_off_rounded),
      SyncPhase.waitingForConnection => (
          statusColors.notApplicable,
          Icons.wifi_off_rounded,
        ),
      SyncPhase.syncing => (theme.colorScheme.primary, Icons.sync_rounded),
      SyncPhase.retryScheduled => (
          statusColors.minorIssue,
          Icons.schedule_rounded,
        ),
      SyncPhase.failed => (statusColors.fail, Icons.cloud_off_outlined),
    };

    return Material(
      color: color.withValues(alpha: 0.10),
      child: InkWell(
        // Manual sync is available whenever there is something to send; a
        // pull-to-refresh gesture is not discoverable enough for this.
        onTap: syncState.hasPendingWork
            ? () => ref
                .read(syncEngineProvider)
                .requestSync(reason: 'user tapped banner')
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (syncState.isBusy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncState.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (syncState.isBusy && syncState.progress != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: syncState.progress,
                          minHeight: 4,
                          backgroundColor: color.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (syncState.hasPendingWork && !syncState.isBusy) ...[
                const SizedBox(width: 8),
                Icon(Icons.refresh_rounded, size: 18, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
