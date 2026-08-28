import 'sync_status.dart';

/// A compressed image attached to an inspection point.
///
/// The file itself lives in app-private storage; only its path and metadata go
/// in the database. Photos sync independently of their parent inspection so a
/// dropped connection halfway through an upload does not lose earlier work.
class InspectionPhoto {
  const InspectionPhoto({
    required this.id,
    required this.inspectionId,
    required this.itemId,
    required this.localPath,
    required this.createdAt,
    this.remoteUrl,
    this.byteSize = 0,
    this.width,
    this.height,
    this.syncStatus = SyncStatus.draftLocal,
    this.lastError,
  });

  final String id;
  final String inspectionId;

  /// Owning checklist item.
  final String itemId;

  /// Absolute path on the device.
  final String localPath;

  /// Set once the backend has stored the file.
  final String? remoteUrl;
  final int byteSize;
  final int? width;
  final int? height;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  final String? lastError;

  bool get isUploaded => remoteUrl != null && syncStatus == SyncStatus.synced;

  String get readableSize {
    if (byteSize <= 0) return '--';
    if (byteSize < 1024) return '$byteSize B';
    if (byteSize < 1024 * 1024) {
      return '${(byteSize / 1024).toStringAsFixed(0)} KB';
    }
    return '${(byteSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  InspectionPhoto copyWith({
    String? remoteUrl,
    int? byteSize,
    int? width,
    int? height,
    SyncStatus? syncStatus,
    String? lastError,
    bool clearError = false,
  }) =>
      InspectionPhoto(
        id: id,
        inspectionId: inspectionId,
        itemId: itemId,
        localPath: localPath,
        createdAt: createdAt,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        byteSize: byteSize ?? this.byteSize,
        width: width ?? this.width,
        height: height ?? this.height,
        syncStatus: syncStatus ?? this.syncStatus,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'inspectionId': inspectionId,
        'itemId': itemId,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'byteSize': byteSize,
        'width': width,
        'height': height,
        'createdAt': createdAt.toIso8601String(),
        'syncStatus': syncStatus.wireValue,
      };

  factory InspectionPhoto.fromJson(Map<String, dynamic> json) =>
      InspectionPhoto(
        id: json['id'] as String,
        inspectionId: json['inspectionId'] as String,
        itemId: json['itemId'] as String,
        localPath: json['localPath'] as String,
        remoteUrl: json['remoteUrl'] as String?,
        byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        syncStatus: SyncStatus.fromWire(json['syncStatus'] as String?),
      );
}
