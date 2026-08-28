import '../../core/network/api_client.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/entities/inspection_photo.dart';

/// Inspection endpoints.
class InspectionApi {
  const InspectionApi(this._client);

  final ApiClient _client;

  /// Submits a completed inspection and returns the server-assigned id.
  ///
  /// The local id travels in the payload so the backend can treat a repeated
  /// call as idempotent — essential when a response is lost after the server
  /// has already committed.
  Future<String> submit(Inspection inspection) async {
    final response = await _client.post(
      '/inspections',
      body: inspection.toJson(),
    );
    return response['id']! as String;
  }

  /// Uploads one photo and returns its CDN URL.
  ///
  /// Addressed by the server-assigned id, so the parent inspection must have
  /// been accepted first — the sync engine enforces that ordering.
  Future<String> uploadPhoto(
    InspectionPhoto photo, {
    required String inspectionRemoteId,
  }) async {
    final response = await _client.uploadFile(
      '/inspections/$inspectionRemoteId/photos',
      filePath: photo.localPath,
      fields: {
        'photoId': photo.id,
        'itemId': photo.itemId,
      },
    );
    return response['url']! as String;
  }
}
