import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_indicators.dart';
import '../../domain/entities/sync_status.dart';
import '../inspection/inspection_controller.dart';
import '../inspection/inspection_session.dart';
import '../inspection/summary_screen.dart';

/// Read-only view of a submitted inspection.
///
/// Reuses [InspectionSummaryView] so a stored inspection is displayed by
/// exactly the code that showed it at review time, with a sync card added on
/// top and a manual retry when the automatic attempts have been used up.
class InspectionDetailScreen extends ConsumerWidget {
  const InspectionDetailScreen({required this.inspectionId, super.key});

  static const String routeName = '/history/detail';

  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSession = ref.watch(inspectionControllerProvider(inspectionId));

    return Scaffold(
      appBar: AppBar(
        title: asyncSession.maybeWhen(
          data: (session) =>
              Text(session.inspection.vehicle.registrationNumber),
          orElse: () => const Text('Inspection'),
        ),
      ),
      body: asyncSession.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(inspectionControllerProvider(inspectionId)),
        ),
        data: (session) => InspectionSummaryView(
          session: session,
          // Submitted inspections are immutable; these callbacks are never
          // reachable because the view hides its edit affordances.
          onEditVehicle: () {},
          onEditChecklist: () {},
          leading: _SyncCard(session: session, inspectionId: inspectionId),
        ),
      ),
    );
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard({required this.session, required this.inspectionId});

  final InspectionSession session;
  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inspection = session.inspection;
    final unsyncedPhotos = inspection.allPhotos
        .where((photo) => photo.syncStatus != SyncStatus.synced)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sync',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                SyncStatusChip(status: inspection.syncStatus),
              ],
            ),
            const SizedBox(height: 10),
            _Line(
              label: 'Submitted',
              value: inspection.submittedAt == null
                  ? 'Not submitted'
                  : Formatters.dateTime(inspection.submittedAt!),
            ),
            _Line(
              label: 'Server reference',
              value: inspection.remoteId ?? 'Not uploaded yet',
            ),
            if (unsyncedPhotos > 0)
              _Line(
                label: 'Photos pending',
                value: '$unsyncedPhotos of ${inspection.photoCount}',
              ),
            if (inspection.lastSyncError != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: context.statusColors.fail,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      inspection.lastSyncError!,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: context.statusColors.fail),
                    ),
                  ),
                ],
              ),
            ],
            if (inspection.syncStatus.isUnsynced) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(
                            inspectionControllerProvider(inspectionId).notifier,
                          )
                          .retrySync();
                      if (context.mounted) {
                        AppMessenger.showInfo(context, 'Queued for upload');
                      }
                    } catch (error) {
                      if (context.mounted) {
                        AppMessenger.showError(context, error);
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Retry sync now'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
