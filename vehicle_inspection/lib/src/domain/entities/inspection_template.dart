import 'grading.dart';

/// A single question on the checklist.
///
/// Points are pure data. Nothing in the UI is written per-point, so growing
/// the checklist from 25 to 209+ entries means shipping a bigger template —
/// not writing more widgets.
class InspectionPoint {
  const InspectionPoint({
    required this.id,
    required this.categoryId,
    required this.code,
    required this.title,
    this.description,
    this.isRequired = true,
    this.allowsNotApplicable = true,
    this.requiresPhotoOnFail = false,
    this.maxPhotos = 3,
    this.weight = 1,
    this.sortOrder = 0,
  });

  final String id;
  final String categoryId;

  /// Stable business code (e.g. `EXT-01`) that survives re-ordering and is what
  /// a backend report would key on.
  final String code;
  final String title;

  /// Optional guidance shown under the title.
  final String? description;

  /// Required points block finalisation until answered.
  final bool isRequired;

  /// Some points (a sunroof on a car without one) can legitimately be skipped.
  final bool allowsNotApplicable;

  /// Evidence policy: a failed point can demand at least one photo.
  final bool requiresPhotoOnFail;
  final int maxPhotos;

  /// Relative importance. A weight of 2 makes the point count double toward
  /// both the obtained and the maximum score.
  final int weight;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'code': code,
        'title': title,
        'description': description,
        'isRequired': isRequired,
        'allowsNotApplicable': allowsNotApplicable,
        'requiresPhotoOnFail': requiresPhotoOnFail,
        'maxPhotos': maxPhotos,
        'weight': weight,
        'sortOrder': sortOrder,
      };

  factory InspectionPoint.fromJson(Map<String, dynamic> json) =>
      InspectionPoint(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        code: json['code'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        isRequired: json['isRequired'] as bool? ?? true,
        allowsNotApplicable: json['allowsNotApplicable'] as bool? ?? true,
        requiresPhotoOnFail: json['requiresPhotoOnFail'] as bool? ?? false,
        maxPhotos: (json['maxPhotos'] as num?)?.toInt() ?? 3,
        weight: (json['weight'] as num?)?.toInt() ?? 1,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// A named group of points, rendered as one section of the checklist.
class InspectionCategory {
  const InspectionCategory({
    required this.id,
    required this.code,
    required this.title,
    required this.points,
    this.iconName,
    this.sortOrder = 0,
  });

  final String id;
  final String code;
  final String title;

  /// Icon is referenced by name so templates stay serialisable; the UI maps
  /// the name onto a concrete [IconData].
  final String? iconName;
  final int sortOrder;
  final List<InspectionPoint> points;

  int get requiredPointCount => points.where((p) => p.isRequired).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'title': title,
        'iconName': iconName,
        'sortOrder': sortOrder,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory InspectionCategory.fromJson(Map<String, dynamic> json) =>
      InspectionCategory(
        id: json['id'] as String,
        code: json['code'] as String,
        title: json['title'] as String,
        iconName: json['iconName'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((e) => InspectionPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A versioned checklist definition.
///
/// The app never assumes one template exists: an inspection stores the
/// template id and version it was captured against, so historical inspections
/// keep rendering correctly after an admin publishes a new revision.
class InspectionTemplate {
  InspectionTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.categories,
    this.description,
    this.isDefault = false,
    this.updatedAt,
    this.gradingRules = GradingRules.standard,
  }) : _pointIndex = {
          for (final category in categories)
            for (final point in category.points) point.id: point,
        };

  final String id;
  final String name;
  final int version;
  final String? description;
  final bool isDefault;
  final DateTime? updatedAt;
  final List<InspectionCategory> categories;

  /// Scoring scale this template is graded with.
  ///
  /// Carrying the rules on the template — rather than hard-coding them in the
  /// grader — is what lets the admin dashboard publish a stricter scale for,
  /// say, commercial vehicles without an app release.
  final GradingRules gradingRules;

  final Map<String, InspectionPoint> _pointIndex;

  /// Every point across every category, in display order.
  List<InspectionPoint> get allPoints => [
        for (final category in categories) ...category.points,
      ];

  int get totalPointCount => _pointIndex.length;

  int get requiredPointCount =>
      _pointIndex.values.where((p) => p.isRequired).length;

  InspectionPoint? pointById(String id) => _pointIndex[id];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'isDefault': isDefault,
        'updatedAt': updatedAt?.toIso8601String(),
        'gradingRules': gradingRules.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(),
      };

  factory InspectionTemplate.fromJson(Map<String, dynamic> json) =>
      InspectionTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        version: (json['version'] as num).toInt(),
        description: json['description'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        // A template without explicit rules falls back to the standard scale.
        gradingRules: json['gradingRules'] == null
            ? GradingRules.standard
            : GradingRules.fromJson(
                json['gradingRules'] as Map<String, dynamic>,
              ),
        categories: (json['categories'] as List<dynamic>? ?? const [])
            .map((e) => InspectionCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
