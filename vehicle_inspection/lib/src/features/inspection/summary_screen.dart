import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_indicators.dart';
import '../../domain/entities/inspection_item.dart';
import '../../domain/entities/inspection_template.dart';
import '../../domain/entities/item_status.dart';
import 'inspection_controller.dart';
import 'inspection_session.dart';

/// Final review before submission.
///
/// Deliberately read-heavy: this is the last chance to catch a mistyped VIN or
/// a point answered by accident, so everything that will be submitted is shown
/// on one screen with a route back to fix it.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({required this.inspectionId, super.key});

  static const String routeName = '/inspection/summary';

  final String inspectionId;

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final inspection = await ref
          .read(inspectionControllerProvider(widget.inspectionId).notifier)
          .submit();

      if (!mounted) return;
      // Drop the new-inspection / checklist / summary routes but keep the root,
      // so Back reaches the dashboard rather than the checklist of a finished
      // inspection. The predicate must be `isFirst`: the dashboard is the root
      // gate's content, not a pushed route, so matching on a route name would
      // match nothing and unwind the entire stack.
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.submitted,
        (route) => route.isFirst,
        arguments: inspection.id,
      );
    } catch (error) {
      if (!mounted) return;
      AppMessenger.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSession =
        ref.watch(inspectionControllerProvider(widget.inspectionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Inspection summary')),
      body: asyncSession.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref
              .invalidate(inspectionControllerProvider(widget.inspectionId)),
        ),
        data: (session) => InspectionSummaryView(
          session: session,
          onEditVehicle: () => Navigator.of(context).pushNamed(
            AppRoutes.editVehicle,
            arguments: widget.inspectionId,
          ),
          onEditChecklist: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: asyncSession.maybeWhen(
        data: (session) => session.inspection.isSubmitted
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit inspection',
                    ),
                  ),
                ),
              ),
        orElse: () => null,
      ),
    );
  }
}

/// The read-only body of an inspection summary.
///
/// Shared by the pre-submission review and the read-only detail screen, so the
/// two can never disagree about what an inspection contains.
class InspectionSummaryView extends StatelessWidget {
  const InspectionSummaryView({
    required this.session,
    required this.onEditVehicle,
    required this.onEditChecklist,
    this.leading,
    super.key,
  });

  final InspectionSession session;
  final VoidCallback onEditVehicle;
  final VoidCallback onEditChecklist;

  /// Optional card rendered above the score, used by the detail screen to show
  /// sync state.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inspection = session.inspection;
    final grading = session.grading;
    final vehicle = inspection.vehicle;
    final readOnly = inspection.isSubmitted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(height: 16),
        ],
        _ScoreCard(session: session),
        const SizedBox(height: 16),

        _SectionCard(
          title: 'Vehicle',
          trailing: readOnly
              ? null
              : TextButton.icon(
                  onPressed: onEditVehicle,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
          child: Column(
            children: [
              _DetailRow(
                label: 'Registration',
                value: vehicle.registrationNumber,
              ),
              _DetailRow(label: 'Make & model', value: vehicle.displayName),
              _DetailRow(
                label: 'Year',
                value: '${vehicle.manufacturingYear}',
              ),
              _DetailRow(label: 'VIN', value: vehicle.vin),
              _DetailRow(
                label: 'Mileage',
                value: Formatters.mileage(vehicle.mileageKm),
              ),
              _DetailRow(
                label: 'Inspection ID',
                value: inspection.referenceNumber,
              ),
              _DetailRow(
                label: 'Evaluator',
                value: inspection.evaluatorName,
              ),
              _DetailRow(
                label: 'Started',
                value: Formatters.dateTime(inspection.createdAt),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _SectionCard(
          title: 'Checklist breakdown',
          trailing: readOnly
              ? null
              : TextButton.icon(
                  onPressed: onEditChecklist,
                  icon: const Icon(Icons.checklist_rounded, size: 16),
                  label: const Text('Edit'),
                ),
          child: Column(
            children: [
              _DetailRow(
                label: 'Total points',
                value: '${grading.totalItems}',
              ),
              _DetailRow(
                label: 'Completed',
                value: '${grading.completedItems}',
              ),
              const Divider(height: 18),
              _CountRow(
                status: ItemStatus.pass,
                count: grading.passCount,
              ),
              _CountRow(
                status: ItemStatus.minorIssue,
                count: grading.minorIssueCount,
              ),
              _CountRow(
                status: ItemStatus.fail,
                count: grading.failCount,
              ),
              _CountRow(
                status: ItemStatus.notApplicable,
                count: grading.notApplicableCount,
              ),
              if (grading.pendingCount > 0)
                _CountRow(
                  status: ItemStatus.pending,
                  count: grading.pendingCount,
                ),
              const Divider(height: 18),
              _DetailRow(
                label: 'Points scored',
                value:
                    '${grading.obtainedPoints} of ${grading.maxPoints}',
              ),
              _DetailRow(
                label: 'Applicable points',
                value: '${grading.scoredItems} '
                    '(N/A excluded)',
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _DefectsSection(session: session),
        const SizedBox(height: 16),

        _PhotosSection(session: session),

        if (!readOnly && !session.canSubmit) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.submitBlockedReason ??
                        'Some points still need attention.',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.session});

  final InspectionSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grading = session.grading;
    final rules = session.template.gradingRules;
    final band = rules.bandFor(grading.percentage);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            GradeBadge(
              gradeCode: grading.hasScore ? grading.gradeCode : null,
              size: 74,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grading.hasScore ? grading.displayPercentage : 'Ungraded',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    grading.hasScore
                        ? '${grading.gradeLabel} - grade ${grading.gradeCode} '
                            '(${rules.displayRange(band)}%)'
                        : 'Answer at least one point to see a score',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProgressSummary(
                    completed: grading.completedItems,
                    total: grading.totalItems,
                    label: 'Checklist',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every point the evaluator marked as a problem, with its comment.
class _DefectsSection extends StatelessWidget {
  const _DefectsSection({required this.session});

  final InspectionSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final defects = <(InspectionPoint, InspectionItem)>[];
    for (final item in session.inspection.items) {
      if (!item.status.isDefect) continue;
      final point = session.template.pointById(item.pointId);
      if (point != null) defects.add((point, item));
    }

    if (defects.isEmpty) {
      return _SectionCard(
        title: 'Issues found',
        child: Row(
          children: [
            Icon(
              Icons.verified_outlined,
              size: 20,
              color: context.statusColors.pass,
            ),
            const SizedBox(width: 10),
            Text(
              'No issues recorded',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return _SectionCard(
      title: 'Issues found (${defects.length})',
      child: Column(
        children: [
          for (final (point, item) in defects)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: StatusPill(status: item.status, compact: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${point.code} - ${point.title}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (item.hasComment)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.comment!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (item.photos.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.photo_camera_back_outlined,
                                  size: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${item.photos.length} photo'
                                  '${item.photos.length == 1 ? '' : 's'}',
                                  style:
                                      theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.session});

  final InspectionSession session;

  @override
  Widget build(BuildContext context) {
    final photos = session.inspection.allPhotos;
    final theme = Theme.of(context);

    return _SectionCard(
      title: 'Photos (${photos.length})',
      child: photos.isEmpty
          ? Text(
              'No photos attached',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                for (final photo in photos)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photo.localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small building blocks
// -----------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
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

class _CountRow extends StatelessWidget {
  const _CountRow({required this.status, required this.count});

  final ItemStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusColors.forStatus(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(status.label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
