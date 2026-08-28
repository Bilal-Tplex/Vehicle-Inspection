import '../entities/inspection_template.dart';

/// Supplies checklist definitions.
///
/// Today a single bundled template is seeded into the database on first run.
/// The interface is already shaped for the admin dashboard, which will publish
/// multiple templates and new versions of them over the API.
abstract interface class TemplateRepository {
  /// Template new inspections should use.
  Future<InspectionTemplate> getActiveTemplate();

  /// Every template held locally, for a future template picker.
  Future<List<InspectionTemplate>> getTemplates();

  /// A specific revision, so a historical inspection renders against the exact
  /// checklist it was captured with.
  Future<InspectionTemplate?> getTemplate(String id, {int? version});

  /// Pulls newer templates from the backend when connectivity allows.
  ///
  /// Returns `true` if anything changed locally. Failing to reach the server
  /// is not an error — the cached template stays in use.
  Future<bool> refreshFromRemote();
}
