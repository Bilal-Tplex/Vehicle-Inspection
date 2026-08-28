import 'inspection_photo.dart';
import 'item_status.dart';

/// The evaluator's answer to one [InspectionPoint].
///
/// An item row exists for every point in the template from the moment the
/// inspection is created, starting at [ItemStatus.pending]. That keeps progress
/// arithmetic trivial and means a template change cannot orphan an answer.
class InspectionItem {
  const InspectionItem({
    required this.id,
    required this.inspectionId,
    required this.pointId,
    this.status = ItemStatus.pending,
    this.comment,
    this.photos = const [],
    this.updatedAt,
  });

  final String id;
  final String inspectionId;
  final String pointId;
  final ItemStatus status;
  final String? comment;
  final List<InspectionPhoto> photos;
  final DateTime? updatedAt;

  bool get isAnswered => status.isAnswered;
  bool get hasComment => comment?.trim().isNotEmpty ?? false;
  bool get hasPhotos => photos.isNotEmpty;

  InspectionItem copyWith({
    ItemStatus? status,
    String? comment,
    bool clearComment = false,
    List<InspectionPhoto>? photos,
    DateTime? updatedAt,
  }) =>
      InspectionItem(
        id: id,
        inspectionId: inspectionId,
        pointId: pointId,
        status: status ?? this.status,
        comment: clearComment ? null : (comment ?? this.comment),
        photos: photos ?? this.photos,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'inspectionId': inspectionId,
        'pointId': pointId,
        'status': status.wireValue,
        'comment': comment,
        'updatedAt': updatedAt?.toIso8601String(),
        'photos': photos.map((p) => p.toJson()).toList(),
      };

  factory InspectionItem.fromJson(Map<String, dynamic> json) => InspectionItem(
        id: json['id'] as String,
        inspectionId: json['inspectionId'] as String,
        pointId: json['pointId'] as String,
        status: ItemStatus.fromWire(json['status'] as String?),
        comment: json['comment'] as String?,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        photos: (json['photos'] as List<dynamic>? ?? const [])
            .map((e) => InspectionPhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
