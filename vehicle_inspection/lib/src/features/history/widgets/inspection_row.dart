import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_indicators.dart';
import '../../../domain/entities/inspection_summary.dart';
import '../../../domain/entities/sync_status.dart';

/// One inspection in a list.
///
/// Tapping a draft resumes the checklist where the evaluator left off; tapping
/// a submitted inspection opens its read-only detail. Routing on the record's
/// own state avoids a second "what do you want to do?" prompt.
class InspectionRow extends StatelessWidget {
  const InspectionRow({required this.summary, super.key});

  final InspectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (summary.isSubmitted) {
            Navigator.of(context).pushNamed(
              AppRoutes.inspectionDetail,
              arguments: summary.id,
            );
          } else {
            Navigator.of(context).pushNamed(
              AppRoutes.checklist,
              arguments: summary.id,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradeBadge(
                gradeCode: summary.isSubmitted ? summary.gradeCode : null,
                percentage: summary.isSubmitted ? summary.scorePercentage : null,
                size: 50,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.registrationNumber,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SyncStatusChip(
                          status: summary.syncStatus,
                          showLabel: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.vehicleName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          summary.referenceNumber,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        Text(
                          '  -  ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          Formatters.relativeDate(summary.displayDate),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (summary.photoCount > 0) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.photo_camera_back_outlined,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${summary.photoCount}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Drafts show how far along they are; submitted ones show
                    // their grade in the badge instead.
                    if (!summary.isSubmitted) ...[
                      const SizedBox(height: 10),
                      ProgressSummary(
                        completed: summary.completedItems,
                        total: summary.totalItems,
                        label: 'Draft',
                      ),
                    ],
                    if (summary.syncStatus == SyncStatus.failed &&
                        summary.lastSyncError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        summary.lastSyncError!,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.error),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
