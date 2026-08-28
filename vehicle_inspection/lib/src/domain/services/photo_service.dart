/// Where an image comes from.
enum PhotoSource { camera, gallery }

/// A photo that has been picked, compressed and written to app-private
/// storage, ready to be recorded against an inspection item.
class CapturedPhoto {
  const CapturedPhoto({
    required this.path,
    required this.byteSize,
    this.width,
    this.height,
  });

  final String path;
  final int byteSize;
  final int? width;
  final int? height;
}

/// Capture and storage of inspection photos.
///
/// Declared in the domain layer so the repository can depend on the capability
/// rather than on `image_picker` and `flutter_image_compress`; tests supply a
/// fake that writes a temp file.
abstract interface class PhotoService {
  /// Opens the camera or gallery, compresses the result and stores it.
  ///
  /// Returns `null` when the evaluator cancels the picker — a cancellation is
  /// not an error and must not surface as one.
  Future<CapturedPhoto?> capture({
    required PhotoSource source,
    required String inspectionId,
  });

  /// Removes a stored file. Safe to call for a path that no longer exists.
  Future<void> deleteFile(String path);

  /// Deletes every photo belonging to an inspection, used when a draft is
  /// discarded so orphaned files cannot accumulate.
  Future<void> deleteInspectionFiles(String inspectionId);
}
