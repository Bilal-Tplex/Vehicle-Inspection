import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_indicators.dart';
import '../../domain/entities/inspection_template.dart';
import '../sync/sync_banner.dart';
import 'inspection_controller.dart';
import 'inspection_session.dart';
import 'widgets/checklist_point_tile.dart';

/// Which points are visible.
enum ChecklistFilter {
  all('All'),
  unanswered('Not checked'),
  issues('Issues');

  const ChecklistFilter(this.label);

  final String label;
}

/// The inspection checklist.
///
/// Categories and points come entirely from the template, and the list is a
/// single flattened, lazily-built sliver — so 209 points cost the same in code
/// as 25 and only the visible rows are ever constructed.
class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({required this.inspectionId, super.key});

  static const String routeName = '/inspection/checklist';

  final String inspectionId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  ChecklistFilter _filter = ChecklistFilter.all;
  final Set<String> _collapsedCategories = {};

  /// Point ids flagged after a blocked submit attempt, so the evaluator can see
  /// exactly what is missing instead of hunting for it.
  Set<String> _highlighted = {};

  @override
  Widget build(BuildContext context) {
    final asyncSession =
        ref.watch(inspectionControllerProvider(widget.inspectionId));

    return Scaffold(
      appBar: AppBar(
        title: asyncSession.when(
          data: (session) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(session.inspection.vehicle.registrationNumber),
              Text(
                session.inspection.vehicle.displayNameWithYear,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          loading: () => const Text('Checklist'),
          error: (_, _) => const Text('Checklist'),
        ),
        actions: [
          asyncSession.maybeWhen(
            data: (session) => session.inspection.isDraft
                ? IconButton(
                    tooltip: 'Discard draft',
                    onPressed: () => _confirmDiscard(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: asyncSession.when(
        loading: () => const LoadingView(message: 'Loading checklist...'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(
            inspectionControllerProvider(widget.inspectionId),
          ),
        ),
        data: _buildBody,
      ),
      bottomNavigationBar: asyncSession.maybeWhen(
        data: _buildBottomBar,
        orElse: () => null,
      ),
    );
  }

  Widget _buildBody(InspectionSession session) {
    final rows = _buildRows(session);

    return Column(
      children: [
        const SyncBanner(),
        _ChecklistHeader(session: session),
        _FilterBar(
          selected: _filter,
          counts: _filterCounts(session),
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Nothing matches this filter',
                  message: 'Switch back to All to see every point.',
                  action: TextButton(
                    onPressed: () =>
                        setState(() => _filter = ChecklistFilter.all),
                    child: const Text('Show all points'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      _buildRow(session, rows[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(InspectionSession session, _ChecklistRow row) {
    switch (row) {
      case _CategoryRow(:final category):
        final (completed, total) = session.progressFor(category);
        return _CategoryHeader(
          category: category,
          completed: completed,
          total: total,
          collapsed: _collapsedCategories.contains(category.id),
          onToggle: () => setState(() {
            if (!_collapsedCategories.remove(category.id)) {
              _collapsedCategories.add(category.id);
            }
          }),
        );

      case _PointRow(:final point):
        final item = session.inspection.itemForPoint(point.id);
        if (item == null) return const SizedBox.shrink();
        final readOnly = session.inspection.isSubmitted;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ChecklistPointTile(
            // Keyed by point so Flutter reuses the right element — and the
            // right comment controller — as the filter changes the list.
            key: ValueKey(point.id),
            point: point,
            item: item,
            readOnly: readOnly,
            highlight: _highlighted.contains(point.id),
            onStatusChanged: (status) => _run(
              () => ref
                  .read(
                    inspectionControllerProvider(widget.inspectionId).notifier,
                  )
                  .setStatus(pointId: point.id, status: status),
              onDone: () => _clearHighlight(point.id),
            ),
            onCommentChanged: (comment) => _run(
              () => ref
                  .read(
                    inspectionControllerProvider(widget.inspectionId).notifier,
                  )
                  .setComment(pointId: point.id, comment: comment),
            ),
            onAddPhoto: (source) => _run(
              () => ref
                  .read(
                    inspectionControllerProvider(widget.inspectionId).notifier,
                  )
                  .addPhoto(pointId: point.id, source: source),
              onDone: () => _clearHighlight(point.id),
            ),
            onDeletePhoto: (photoId) => _run(
              () => ref
                  .read(
                    inspectionControllerProvider(widget.inspectionId).notifier,
                  )
                  .removePhoto(photoId),
            ),
            onReplacePhoto: (photoId, source) => _run(
              () => ref
                  .read(
                    inspectionControllerProvider(widget.inspectionId).notifier,
                  )
                  .replacePhoto(
                    pointId: point.id,
                    photoId: photoId,
                    source: source,
                  ),
            ),
          ),
        );
    }
  }

  Widget _buildBottomBar(InspectionSession session) {
    if (session.inspection.isSubmitted) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final blockedReason = session.submitBlockedReason;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // The primary action spans the bar; the button theme no longer forces
          // that on every button, so ask for it where it is wanted.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (blockedReason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        blockedReason,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              // Always enabled: tapping it when something is missing jumps to
              // the offending points, which is more useful than a dead button.
              onPressed: () => _reviewAndSubmit(session),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review & submit'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _reviewAndSubmit(InspectionSession session) {
    if (!session.canSubmit) {
      final blocking = <String>{
        ...session.blockingPoints.map((p) => p.id),
        ...session.pointsNeedingPhotos.map((p) => p.id),
      };

      setState(() {
        _highlighted = blocking;
        _filter = session.blockingPoints.isNotEmpty
            ? ChecklistFilter.unanswered
            : ChecklistFilter.issues;
        // Expand everything so a collapsed category cannot hide the problem.
        _collapsedCategories.clear();
      });
      AppMessenger.showInfo(
        context,
        session.submitBlockedReason ?? 'Some points still need attention.',
      );
      return;
    }

    Navigator.of(context).pushNamed(
      AppRoutes.summary,
      arguments: widget.inspectionId,
    );
  }

  void _clearHighlight(String pointId) {
    if (!_highlighted.contains(pointId)) return;
    setState(() => _highlighted = {..._highlighted}..remove(pointId));
  }

  /// Runs a controller action and reports failures without tearing down the
  /// screen — the checklist stays exactly where the evaluator left it.
  Future<void> _run(
    Future<void> Function() action, {
    VoidCallback? onDone,
  }) async {
    try {
      await action();
      onDone?.call();
    } catch (error) {
      if (!mounted) return;
      AppMessenger.showError(context, error);
    }
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
          'The inspection and its photos will be permanently removed from '
          'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) return;

    try {
      await ref
          .read(inspectionControllerProvider(widget.inspectionId).notifier)
          .discard();
    } catch (error) {
      if (!mounted) return;
      AppMessenger.showError(this.context, error);
      return;
    }
    if (!mounted) return;
    Navigator.of(this.context).pop();
  }

  // ---------------------------------------------------------------------------
  // Row construction
  // ---------------------------------------------------------------------------

  /// Flattens categories and points into one list, honouring the filter and
  /// collapsed sections. A category header is dropped when the filter leaves it
  /// with nothing to show.
  List<_ChecklistRow> _buildRows(InspectionSession session) {
    final rows = <_ChecklistRow>[];

    for (final category in session.template.categories) {
      final visiblePoints =
          category.points.where((p) => _matchesFilter(session, p)).toList();
      if (visiblePoints.isEmpty) continue;

      rows.add(_CategoryRow(category));
      if (_collapsedCategories.contains(category.id)) continue;
      rows.addAll(visiblePoints.map(_PointRow.new));
    }
    return rows;
  }

  bool _matchesFilter(InspectionSession session, InspectionPoint point) {
    final item = session.inspection.itemForPoint(point.id);
    if (item == null) return false;
    return switch (_filter) {
      ChecklistFilter.all => true,
      ChecklistFilter.unanswered => !item.isAnswered,
      ChecklistFilter.issues => item.status.isDefect,
    };
  }

  Map<ChecklistFilter, int> _filterCounts(InspectionSession session) {
    var unanswered = 0;
    var issues = 0;
    for (final item in session.inspection.items) {
      if (!item.isAnswered) unanswered++;
      if (item.status.isDefect) issues++;
    }
    return {
      ChecklistFilter.all: session.inspection.totalItems,
      ChecklistFilter.unanswered: unanswered,
      ChecklistFilter.issues: issues,
    };
  }
}

// -----------------------------------------------------------------------------
// Row model
// -----------------------------------------------------------------------------

sealed class _ChecklistRow {
  const _ChecklistRow();
}

class _CategoryRow extends _ChecklistRow {
  const _CategoryRow(this.category);

  final InspectionCategory category;
}

class _PointRow extends _ChecklistRow {
  const _PointRow(this.point);

  final InspectionPoint point;
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _ChecklistHeader extends StatelessWidget {
  const _ChecklistHeader({required this.session});

  final InspectionSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grading = session.grading;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: ProgressSummary(
              completed: session.inspection.completedItems,
              total: session.inspection.totalItems,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Live score',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                grading.hasScore ? grading.displayPercentage : '--',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Grade ${grading.gradeCode}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final ChecklistFilter selected;
  final Map<ChecklistFilter, int> counts;
  final ValueChanged<ChecklistFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          for (final filter in ChecklistFilter.values) ...[
            ChoiceChip(
              label: Text('${filter.label} (${counts[filter] ?? 0})'),
              selected: selected == filter,
              onSelected: (_) => onChanged(filter),
              labelStyle: const TextStyle(fontSize: 12.5),
              visualDensity: VisualDensity.compact,
            ),
            if (filter != ChecklistFilter.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.completed,
    required this.total,
    required this.collapsed,
    required this.onToggle,
  });

  final InspectionCategory category;
  final int completed;
  final int total;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Icon names come from template data, so a new category shipped by the
  /// admin dashboard renders sensibly without an app release.
  IconData get _icon => switch (category.iconName) {
        'exterior' => Icons.directions_car_outlined,
        'interior' => Icons.airline_seat_recline_normal_outlined,
        'engine' => Icons.settings_suggest_outlined,
        'tires' => Icons.tire_repair_outlined,
        'safety' => Icons.health_and_safety_outlined,
        _ => Icons.checklist_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isComplete = total > 0 && completed >= total;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Icon(_icon, size: 19, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completed/$total',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isComplete
                      ? context.statusColors.pass
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
