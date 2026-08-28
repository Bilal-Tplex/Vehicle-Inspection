import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../domain/entities/grading.dart';
import '../../../domain/entities/inspection_template.dart';
import '../app_database.dart';

/// Reads and writes checklist definitions.
///
/// Templates are stored fully normalised, so the app can eventually query
/// points directly (search, per-category counts) instead of parsing a blob on
/// every open — which matters once a template holds 209 of them.
class TemplateDao {
  const TemplateDao(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<bool> exists(String id, int version) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.templates,
      columns: ['id'],
      where: 'id = ? AND version = ?',
      whereArgs: [id, version],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Inserts or replaces a template and its whole definition atomically.
  ///
  /// Marking a template default clears the flag on every other row first, so
  /// there is exactly one active default at any time.
  Future<void> upsert(InspectionTemplate template, {bool isActive = true}) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      if (template.isDefault) {
        await txn.update(
          Tables.templates,
          {'is_default': 0},
          where: 'id != ? OR version != ?',
          whereArgs: [template.id, template.version],
        );
      }

      await txn.insert(
        Tables.templates,
        {
          'id': template.id,
          'version': template.version,
          'name': template.name,
          'description': template.description,
          'is_default': template.isDefault ? 1 : 0,
          'is_active': isActive ? 1 : 0,
          'grading_rules': jsonEncode(template.gradingRules.toJson()),
          'updated_at': template.updatedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Re-seeding a version replaces its definition wholesale; deleting first
      // removes points an admin may have dropped from the revision.
      await txn.delete(
        Tables.templateCategories,
        where: 'template_id = ? AND template_version = ?',
        whereArgs: [template.id, template.version],
      );
      await txn.delete(
        Tables.templatePoints,
        where: 'template_id = ? AND template_version = ?',
        whereArgs: [template.id, template.version],
      );

      final batch = txn.batch();
      for (final category in template.categories) {
        batch.insert(Tables.templateCategories, {
          'template_id': template.id,
          'template_version': template.version,
          'id': category.id,
          'code': category.code,
          'title': category.title,
          'icon_name': category.iconName,
          'sort_order': category.sortOrder,
        });
        for (final point in category.points) {
          batch.insert(Tables.templatePoints, {
            'template_id': template.id,
            'template_version': template.version,
            'id': point.id,
            'category_id': point.categoryId,
            'code': point.code,
            'title': point.title,
            'description': point.description,
            'is_required': point.isRequired ? 1 : 0,
            'allows_na': point.allowsNotApplicable ? 1 : 0,
            'requires_photo_on_fail': point.requiresPhotoOnFail ? 1 : 0,
            'max_photos': point.maxPhotos,
            'weight': point.weight,
            'sort_order': point.sortOrder,
          });
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Template new inspections should use: the default if one is flagged,
  /// otherwise the most recent active revision.
  Future<InspectionTemplate?> findActive() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.templates,
      where: 'is_active = 1',
      orderBy: 'is_default DESC, version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(db, rows.first);
  }

  /// A specific revision. Omitting [version] returns the newest one.
  Future<InspectionTemplate?> findById(String id, {int? version}) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.templates,
      where: version == null ? 'id = ?' : 'id = ? AND version = ?',
      whereArgs: version == null ? [id] : [id, version],
      orderBy: 'version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(db, rows.first);
  }

  Future<List<InspectionTemplate>> findAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.templates,
      orderBy: 'is_default DESC, name ASC, version DESC',
    );
    final templates = <InspectionTemplate>[];
    for (final row in rows) {
      templates.add(await _hydrate(db, row));
    }
    return templates;
  }

  /// Assembles a template from its three tables in two queries, then groups in
  /// memory — cheaper and simpler than one join per category.
  Future<InspectionTemplate> _hydrate(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final id = row['id']! as String;
    final version = row['version']! as int;

    final categoryRows = await db.query(
      Tables.templateCategories,
      where: 'template_id = ? AND template_version = ?',
      whereArgs: [id, version],
      orderBy: 'sort_order ASC',
    );
    final pointRows = await db.query(
      Tables.templatePoints,
      where: 'template_id = ? AND template_version = ?',
      whereArgs: [id, version],
      orderBy: 'sort_order ASC',
    );

    final pointsByCategory = <String, List<InspectionPoint>>{};
    for (final pointRow in pointRows) {
      final point = InspectionPoint(
        id: pointRow['id']! as String,
        categoryId: pointRow['category_id']! as String,
        code: pointRow['code']! as String,
        title: pointRow['title']! as String,
        description: pointRow['description'] as String?,
        isRequired: (pointRow['is_required'] as int? ?? 1) == 1,
        allowsNotApplicable: (pointRow['allows_na'] as int? ?? 1) == 1,
        requiresPhotoOnFail:
            (pointRow['requires_photo_on_fail'] as int? ?? 0) == 1,
        maxPhotos: pointRow['max_photos'] as int? ?? 3,
        weight: pointRow['weight'] as int? ?? 1,
        sortOrder: pointRow['sort_order'] as int? ?? 0,
      );
      pointsByCategory.putIfAbsent(point.categoryId, () => []).add(point);
    }

    final categories = categoryRows.map((categoryRow) {
      final categoryId = categoryRow['id']! as String;
      return InspectionCategory(
        id: categoryId,
        code: categoryRow['code']! as String,
        title: categoryRow['title']! as String,
        iconName: categoryRow['icon_name'] as String?,
        sortOrder: categoryRow['sort_order'] as int? ?? 0,
        points: pointsByCategory[categoryId] ?? const [],
      );
    }).toList();

    return InspectionTemplate(
      id: id,
      version: version,
      name: row['name']! as String,
      description: row['description'] as String?,
      isDefault: (row['is_default'] as int? ?? 0) == 1,
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.tryParse(row['updated_at']! as String),
      gradingRules: _decodeRules(row['grading_rules'] as String?),
      categories: categories,
    );
  }

  /// A corrupt or missing rules column must not make the template unusable —
  /// fall back to the standard scale rather than throwing.
  GradingRules _decodeRules(String? encoded) {
    if (encoded == null || encoded.isEmpty) return GradingRules.standard;
    try {
      return GradingRules.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } catch (_) {
      return GradingRules.standard;
    }
  }
}
