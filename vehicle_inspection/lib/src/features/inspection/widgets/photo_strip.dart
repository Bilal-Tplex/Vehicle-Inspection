import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../domain/entities/inspection_photo.dart';
import '../../../domain/entities/sync_status.dart';
import '../../../domain/services/photo_service.dart';

/// Horizontal thumbnails plus an add button.
///
/// Thumbnails are read straight from local storage, so they render with no
/// connection — the whole point of compressing at capture time.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    required this.photos,
    required this.maxPhotos,
    required this.readOnly,
    this.onAdd,
    this.onDelete,
    this.onReplace,
    super.key,
  });

  final List<InspectionPhoto> photos;
  final int maxPhotos;
  final bool readOnly;
  final ValueChanged<PhotoSource>? onAdd;
  final ValueChanged<String>? onDelete;
  final void Function(String photoId, PhotoSource source)? onReplace;

  bool get _canAddMore => !readOnly && photos.length < maxPhotos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty && readOnly) return const SizedBox.shrink();

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: photos.length + (_canAddMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index >= photos.length) {
            return _AddPhotoButton(
              remaining: maxPhotos - photos.length,
              onPick: (source) => onAdd?.call(source),
            );
          }
          final photo = photos[index];
          return _PhotoThumbnail(
            photo: photo,
            readOnly: readOnly,
            onTap: () => _openPreview(context, photo),
          );
        },
      ),
    );
  }

  Future<void> _openPreview(BuildContext context, InspectionPhoto photo) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PhotoPreviewDialog(
        photo: photo,
        readOnly: readOnly,
        onDelete: onDelete == null
            ? null
            : () {
                Navigator.of(dialogContext).pop();
                onDelete!(photo.id);
              },
        onReplace: onReplace == null
            ? null
            : (source) {
                Navigator.of(dialogContext).pop();
                onReplace!(photo.id, source);
              },
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({
    required this.photo,
    required this.readOnly,
    required this.onTap,
  });

  final InspectionPhoto photo;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(photo.localPath),
              width: 78,
              height: 78,
              fit: BoxFit.cover,
              // A file can vanish (storage cleaner, restore); show a
              // placeholder rather than crashing the checklist.
              errorBuilder: (_, _, _) => Container(
                width: 78,
                height: 78,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (photo.syncStatus != SyncStatus.draftLocal)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  photo.syncStatus == SyncStatus.synced
                      ? Icons.cloud_done_outlined
                      : photo.syncStatus == SyncStatus.failed
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_upload_outlined,
                  size: 12,
                  color: context.statusColors.forSync(photo.syncStatus),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.remaining, required this.onPick});

  final int remaining;
  final ValueChanged<PhotoSource> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showSourceSheet(context),
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Text(
              '$remaining left',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSourceSheet(BuildContext context) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(PhotoSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) onPick(source);
  }
}

class _PhotoPreviewDialog extends StatelessWidget {
  const _PhotoPreviewDialog({
    required this.photo,
    required this.readOnly,
    this.onDelete,
    this.onReplace,
  });

  final InspectionPhoto photo;
  final bool readOnly;
  final VoidCallback? onDelete;
  final ValueChanged<PhotoSource>? onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.file(
                File(photo.localPath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.data_usage_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  photo.readableSize,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (photo.width != null && photo.height != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${photo.width} x ${photo.height}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  photo.syncStatus.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.statusColors.forSync(photo.syncStatus),
                  ),
                ),
              ],
            ),
          ),
          if (!readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  if (onReplace != null)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => onReplace!(PhotoSource.camera),
                        icon: const Icon(Icons.cameraswitch_outlined, size: 18),
                        label: const Text('Replace'),
                      ),
                    ),
                  if (onDelete != null)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete'),
                      ),
                    ),
                ],
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
