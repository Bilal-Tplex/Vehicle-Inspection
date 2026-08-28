import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/entities/item_status.dart';
import '../../domain/entities/sync_status.dart';

/// Small filled label for a checklist answer.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, this.compact = false, super.key});

  final ItemStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColors.forStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12.5,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Where a record stands in the sync pipeline.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({required this.status, this.showLabel = true, super.key});

  final SyncStatus status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColors.forSync(status);
    final icon = switch (status) {
      SyncStatus.synced => Icons.cloud_done_outlined,
      SyncStatus.syncing => Icons.cloud_upload_outlined,
      SyncStatus.pending => Icons.cloud_queue_outlined,
      SyncStatus.failed => Icons.cloud_off_outlined,
      SyncStatus.draftLocal => Icons.edit_note_outlined,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// Letter grade in a coloured square, used on summaries and history rows.
class GradeBadge extends StatelessWidget {
  const GradeBadge({
    required this.gradeCode,
    this.percentage,
    this.size = 52,
    super.key,
  });

  final String? gradeCode;
  final double? percentage;
  final double size;

  @override
  Widget build(BuildContext context) {
    final statusColors = context.statusColors;
    final code = gradeCode ?? '-';

    // Colour follows the letter, so a grade is readable at a glance without
    // reading the number next to it.
    final color = switch (code) {
      'A' => statusColors.pass,
      'B' => statusColors.pass,
      'C' => statusColors.minorIssue,
      'D' => statusColors.minorIssue,
      'F' => statusColors.fail,
      _ => statusColors.pending,
    };

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            code,
            style: TextStyle(
              color: color,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          if (percentage != null)
            Text(
              '${percentage!.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: size * 0.19,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// Progress bar with a `15/25 completed` caption.
class ProgressSummary extends StatelessWidget {
  const ProgressSummary({
    required this.completed,
    required this.total,
    this.label,
    super.key,
  });

  final int completed;
  final int total;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = total == 0 ? 0.0 : completed / total;
    final isComplete = total > 0 && completed >= total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label ?? 'Progress',
              style: theme.textTheme.labelLarge,
            ),
            Text(
              '$completed/$total completed',
              style: theme.textTheme.labelLarge?.copyWith(
                color: isComplete
                    ? context.statusColors.pass
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 7,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              isComplete
                  ? context.statusColors.pass
                  : theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
