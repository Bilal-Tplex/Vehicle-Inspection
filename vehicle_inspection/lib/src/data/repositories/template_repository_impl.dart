import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../core/error/failure_mapper.dart';
import '../../core/error/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/inspection_template.dart';
import '../../domain/repositories/template_repository.dart';
import '../local/daos/template_dao.dart';
import '../remote/template_api.dart';

/// Serves checklist definitions from the local database, seeding it from a
/// bundled asset the first time the app runs.
///
/// The asset is a stand-in for the admin dashboard, not a permanent design: it
/// has exactly the JSON shape the API returns, so when the backend starts
/// publishing templates, [refreshFromRemote] overwrites the seed and nothing
/// else in the app is aware anything changed.
class TemplateRepositoryImpl implements TemplateRepository {
  TemplateRepositoryImpl({
    required TemplateDao dao,
    required TemplateApi api,
    AssetBundle? bundle,
    String assetPath = defaultAssetPath,
  })  : _dao = dao,
        _api = api,
        _bundle = bundle,
        _assetPath = assetPath;

  static const String defaultAssetPath =
      'assets/templates/standard_inspection_v1.json';

  final TemplateDao _dao;
  final TemplateApi _api;
  final AssetBundle? _bundle;
  final String _assetPath;

  /// Cached so the checklist screen does not re-read three tables on rebuild.
  InspectionTemplate? _cached;

  @override
  Future<InspectionTemplate> getActiveTemplate() async {
    final cached = _cached;
    if (cached != null) return cached;

    var template = await _dao.findActive();
    template ??= await _seedFromAsset();

    if (template == null) {
      throw const StorageFailure(
        message: 'No inspection checklist is available on this device.',
      );
    }
    return _cached = template;
  }

  @override
  Future<List<InspectionTemplate>> getTemplates() => _dao.findAll();

  @override
  Future<InspectionTemplate?> getTemplate(String id, {int? version}) =>
      _dao.findById(id, version: version);

  @override
  Future<bool> refreshFromRemote() async {
    try {
      final remote = await _api.fetchTemplates();
      if (remote.isEmpty) return false;

      var changed = false;
      for (final template in remote) {
        // Versions are immutable: only a genuinely new revision is written, so
        // re-fetching costs nothing and never disturbs completed inspections.
        if (await _dao.exists(template.id, template.version)) continue;
        await _dao.upsert(template);
        changed = true;
      }

      if (changed) _cached = null;
      return changed;
    } catch (error) {
      // Templates are cached, so a failed refresh is not a user-facing error.
      AppLogger.warn(
        'Template refresh failed: ${mapToFailure(error).message}',
        scope: 'template',
      );
      return false;
    }
  }

  /// Loads the bundled checklist into SQLite on first launch.
  Future<InspectionTemplate?> _seedFromAsset() async {
    try {
      final raw = await (_bundle ?? rootBundle).loadString(_assetPath);
      final template = InspectionTemplate.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      await _dao.upsert(template);
      AppLogger.info(
        'Seeded template ${template.id} v${template.version} '
        '(${template.totalPointCount} points)',
        scope: 'template',
      );
      return template;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to seed the bundled template',
        scope: 'template',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
