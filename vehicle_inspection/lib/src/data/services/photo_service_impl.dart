import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/services/photo_service.dart';

/// Captures photos, compresses them, and stores them in app-private storage.
///
/// Compression happens at capture time rather than at upload time on purpose.
/// An evaluator can shoot 40 photos in a basement with no signal; if the
/// originals were kept, the device would fill up and the eventual upload would
/// be far slower. Compressing once, immediately, bounds both.
///
/// Files live under the app's documents directory, keyed by inspection, so
/// discarding an inspection is a single directory delete.
class PhotoServiceImpl implements PhotoService {
  PhotoServiceImpl({
    ImagePicker? picker,
    Uuid? uuid,
  })  : _picker = picker ?? ImagePicker(),
        _uuid = uuid ?? const Uuid();

  final ImagePicker _picker;
  final Uuid _uuid;

  Directory? _rootDirectory;

  @override
  Future<CapturedPhoto?> capture({
    required PhotoSource source,
    required String inspectionId,
  }) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Let the platform hand back full quality; the compression step below
        // is the single place that decides the final size.
        imageQuality: 100,
      );
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error(
        'Image picker failed (${error.code})',
        scope: 'photo',
        error: error,
        stackTrace: stackTrace,
      );
      // A denied permission needs different advice from a broken camera.
      final denied = error.code == 'camera_access_denied' ||
          error.code == 'photo_access_denied';
      throw MediaFailure(
        message: denied
            ? 'Permission denied. Enable camera and photo access in Settings.'
            : 'Could not open the camera on this device.',
        cause: error,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Image picker failed',
        scope: 'photo',
        error: error,
        stackTrace: stackTrace,
      );
      throw MediaFailure(
        message: 'Could not open the camera.',
        cause: error,
      );
    }

    // Cancelling the picker is a normal outcome, not an error.
    if (picked == null) return null;

    try {
      final directory = await _directoryFor(inspectionId);
      final targetPath = p.join(directory.path, '${_uuid.v4()}.jpg');

      final compressed = await FlutterImageCompress.compressAndGetFile(
        picked.path,
        targetPath,
        quality: AppConstants.photoJpegQuality,
        minWidth: AppConstants.photoMaxDimension,
        minHeight: AppConstants.photoMaxDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      // Compression is best-effort: if the plugin cannot handle the file we
      // still keep the photo rather than losing the evaluator's evidence.
      final storedPath = compressed?.path ?? await _copyOriginal(picked, targetPath);
      final file = File(storedPath);
      final byteSize = await file.length();

      final original = await File(picked.path).length();
      AppLogger.debug(
        'Photo stored: ${_kb(original)} -> ${_kb(byteSize)}',
        scope: 'photo',
      );

      final size = await _readDimensions(file);

      return CapturedPhoto(
        path: storedPath,
        byteSize: byteSize,
        width: size?.$1,
        height: size?.$2,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Photo processing failed',
        scope: 'photo',
        error: error,
        stackTrace: stackTrace,
      );
      throw MediaFailure(
        message: 'Could not save the photo. Check available storage.',
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (error) {
      // A file we cannot delete is a leak, not a failure the evaluator can act
      // on. Log it and let the operation succeed.
      AppLogger.warn('Could not delete $path', scope: 'photo', error: error);
    }
  }

  @override
  Future<void> deleteInspectionFiles(String inspectionId) async {
    try {
      final directory = await _directoryFor(inspectionId, create: false);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    } catch (error) {
      AppLogger.warn(
        'Could not remove photo directory for $inspectionId',
        scope: 'photo',
        error: error,
      );
    }
  }

  Future<Directory> _directoryFor(
    String inspectionId, {
    bool create = true,
  }) async {
    final root = _rootDirectory ??= Directory(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        AppConstants.photoDirectoryName,
      ),
    );
    final directory = Directory(p.join(root.path, inspectionId));
    if (create && !directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> _copyOriginal(XFile picked, String targetPath) async {
    await File(picked.path).copy(targetPath);
    return targetPath;
  }

  /// Reads pixel dimensions from the JPEG header without decoding the bitmap.
  ///
  /// Best-effort: dimensions are metadata for the report, never a reason to
  /// reject an otherwise valid photo.
  Future<(int, int)?> _readDimensions(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      return size;
    } catch (error) {
      AppLogger.debug('Could not read image dimensions: $error', scope: 'photo');
      return null;
    }
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} KB';
}
