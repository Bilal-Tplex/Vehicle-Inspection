import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_indicators.dart';
import '../../domain/entities/sync_status.dart';
import 'inspection_controller.dart';

/// Confirmation shown immediately after submission.
///
/// The inspection ID, score and grade are all available here with no network
/// call, because grading happened on the device and the reference number was
/// generated when the inspection was created. The only thing that depends on
/// connectivity is the sync line — and it says so plainly rather than
/// pretending the submission failed.
class SubmittedScreen extends ConsumerWidget {
  const SubmittedScreen({required this.inspectionId, super.key});

  static const String routeName = '/inspection/submitted';

  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncSession = ref.watch(inspectionControllerProvider(inspectionId));

    return Scaffold(
      body: SafeArea(
        child: asyncSession.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(error: error),
          data: (session) {
            final inspection = session.inspection;
            final grading = session.grading;

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            color: context.statusColors.pass
                                .withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 44,
                            color: context.statusColors.pass,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Inspection submitted',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${inspection.vehicle.registrationNumber} - '
                        '${inspection.vehicle.displayName}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GradeBadge(
                                    gradeCode: grading.gradeCode,
                                    size: 64,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          grading.displayPercentage,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            height: 1.1,
                                          ),
                                        ),
                                        Text(
                                          '${grading.gradeLabel} - '
                                          '${grading.obtainedPoints} of '
                                          '${grading.maxPoints} points',
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 28),
                              _InfoRow(
                                label: 'Inspection ID',
                                value: inspection.referenceNumber,
                              ),
                              if (inspection.remoteId != null)
                                _InfoRow(
                                  label: 'Server reference',
                                  value: inspection.remoteId!,
                                ),
                              const SizedBox(height: 12),
                              _SyncRow(inspectionId: inspectionId),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (inspection.syncStatus != SyncStatus.synced)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.save_outlined,
                                size: 19,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Saved on this device. It will upload '
                                  'automatically once you are back online.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pushReplacementNamed(AppRoutes.newInspection),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Start another inspection'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        child: const Text('Back to dashboard'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live sync line that updates as the engine works through the queue.
class _SyncRow extends ConsumerWidget {
  const _SyncRow({required this.inspectionId});

  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(inspectionControllerProvider(inspectionId)).value;
    if (session == null) return const SizedBox.shrink();

    final status = session.inspection.syncStatus;
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          'Sync status',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        SyncStatusChip(status: status),
        if (status == SyncStatus.failed) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => ref
                .read(inspectionControllerProvider(inspectionId).notifier)
                .retrySync(),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}
