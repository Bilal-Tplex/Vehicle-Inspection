import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../domain/entities/inspection_item.dart';
import '../../../domain/entities/inspection_template.dart';
import '../../../domain/entities/item_status.dart';
import '../../../domain/services/photo_service.dart';
import 'photo_strip.dart';

/// One checklist point, rendered entirely from template data.
///
/// This is the single widget behind every inspection point. Growing the
/// checklist to 209 points adds rows to the template, not classes to the
/// codebase — which is precisely the property the brief asks for.
class ChecklistPointTile extends StatefulWidget {
  const ChecklistPointTile({
    required this.point,
    required this.item,
    required this.readOnly,
    required this.onStatusChanged,
    required this.onCommentChanged,
    required this.onAddPhoto,
    required this.onDeletePhoto,
    required this.onReplacePhoto,
    this.highlight = false,
    super.key,
  });

  final InspectionPoint point;
  final InspectionItem item;
  final bool readOnly;

  /// Set to draw attention to a point that is blocking submission.
  final bool highlight;

  final ValueChanged<ItemStatus> onStatusChanged;
  final ValueChanged<String?> onCommentChanged;
  final ValueChanged<PhotoSource> onAddPhoto;
  final ValueChanged<String> onDeletePhoto;
  final void Function(String photoId, PhotoSource source) onReplacePhoto;

  @override
  State<ChecklistPointTile> createState() => _ChecklistPointTileState();
}

class _ChecklistPointTileState extends State<ChecklistPointTile> {
  late final TextEditingController _commentController =
      TextEditingController(text: widget.item.comment ?? '');
  final FocusNode _commentFocus = FocusNode();

  Timer? _debounce;
  late bool _showComment = widget.item.hasComment;

  @override
  void initState() {
    super.initState();
    _commentFocus.addListener(() {
      // Flush immediately when the field loses focus so a comment is never
      // left unsaved because the evaluator moved on within the debounce window.
      if (!_commentFocus.hasFocus) _flushComment();
    });
  }

  @override
  void didUpdateWidget(covariant ChecklistPointTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.item.comment ?? '';
    // Only adopt external changes while the evaluator is not typing, otherwise
    // a rebuild would fight the cursor.
    if (!_commentFocus.hasFocus && incoming != _commentController.text) {
      _commentController.text = incoming;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _onCommentTyped(String value) {
    // Debounced: a comment write re-grades and re-reads the inspection, which
    // is wasteful on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flushComment);
  }

  void _flushComment() {
    _debounce?.cancel();
    final text = _commentController.text.trim();
    if (text == (widget.item.comment ?? '').trim()) return;
    widget.onCommentChanged(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = context.statusColors;
    final statuses = widget.point.allowsNotApplicable
        ? ItemStatus.selectable
        : ItemStatus.selectable
            .where((s) => s != ItemStatus.notApplicable)
            .toList();

    final needsPhoto = widget.point.requiresPhotoOnFail &&
        widget.item.status == ItemStatus.fail &&
        widget.item.photos.isEmpty;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: widget.highlight
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: widget.highlight ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.point.code,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                          if (!widget.point.isRequired) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Optional',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.75),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.point.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (widget.item.isAnswered) ...[
                  const SizedBox(width: 8),
                  StatusPillMini(status: widget.item.status),
                ],
              ],
            ),
            if (widget.point.description != null) ...[
              const SizedBox(height: 5),
              Text(
                widget.point.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _StatusSelector(
              statuses: statuses,
              selected: widget.item.status,
              enabled: !widget.readOnly,
              onChanged: widget.onStatusChanged,
            ),
            if (needsPhoto) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 15,
                    color: statusColors.fail,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'A photo is required for this failed point.',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: statusColors.fail),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (_showComment || widget.item.hasComment)
              TextField(
                controller: _commentController,
                focusNode: _commentFocus,
                enabled: !widget.readOnly,
                onChanged: _onCommentTyped,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Add a note about this point',
                  prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 38, minHeight: 32),
                ),
                style: theme.textTheme.bodySmall,
              )
            else if (!widget.readOnly)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _showComment = true);
                    // Open the keyboard straight away; requiring a second tap
                    // on the field is friction on a small screen.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _commentFocus.requestFocus(),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add_comment_outlined, size: 16),
                  label: const Text('Add comment'),
                ),
              ),
            if (widget.item.photos.isNotEmpty || !widget.readOnly) ...[
              const SizedBox(height: 10),
              PhotoStrip(
                photos: widget.item.photos,
                maxPhotos: widget.point.maxPhotos,
                readOnly: widget.readOnly,
                onAdd: widget.onAddPhoto,
                onDelete: widget.onDeletePhoto,
                onReplace: widget.onReplacePhoto,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Four-way status selector.
class _StatusSelector extends StatelessWidget {
  const _StatusSelector({
    required this.statuses,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final List<ItemStatus> statuses;
  final ItemStatus selected;
  final bool enabled;
  final ValueChanged<ItemStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final status in statuses) ...[
          Expanded(
            child: _StatusButton(
              status: status,
              isSelected: selected == status,
              enabled: enabled,
              // Tapping the selected status again clears it, which is the only
              // way back to "not checked" after a mis-tap.
              onTap: () => onChanged(
                selected == status ? ItemStatus.pending : status,
              ),
            ),
          ),
          if (status != statuses.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final ItemStatus status;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusColors.forStatus(status);
    final label = switch (status) {
      ItemStatus.pass => 'Pass',
      ItemStatus.minorIssue => 'Minor',
      ItemStatus.fail => 'Fail',
      ItemStatus.notApplicable => 'N/A',
      ItemStatus.pending => '-',
    };

    return Semantics(
      selected: isSelected,
      button: true,
      label: '${status.label} for this point',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isSelected ? context.statusColors.onStatus : color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact dot-and-label used in the tile header.
class StatusPillMini extends StatelessWidget {
  const StatusPillMini({required this.status, super.key});

  final ItemStatus status;

  @override
  Widget build(BuildContext context) {
    final color = context.statusColors.forStatus(status);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
