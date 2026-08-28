import '../../core/network/api_client.dart';
import '../../domain/entities/inspection_template.dart';

/// Checklist template endpoints.
///
/// This is the seam the admin dashboard will plug into: when it starts
/// publishing templates, this call returns them and the seeded asset becomes a
/// first-run fallback rather than the source of truth. Nothing above this
/// class needs to change.
class TemplateApi {
  const TemplateApi(this._client);

  final ApiClient _client;

  Future<List<InspectionTemplate>> fetchTemplates() async {
    final response = await _client.get('/templates');
    final raw = response['templates'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => InspectionTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
