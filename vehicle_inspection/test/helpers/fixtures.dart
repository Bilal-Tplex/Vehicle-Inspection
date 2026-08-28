import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vehicle_inspection/src/core/error/exceptions.dart';
import 'package:vehicle_inspection/src/core/network/api_client.dart';
import 'package:vehicle_inspection/src/data/local/app_database.dart';
import 'package:vehicle_inspection/src/domain/entities/evaluator.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_template.dart';
import 'package:vehicle_inspection/src/domain/entities/vehicle.dart';
import 'package:vehicle_inspection/src/domain/repositories/template_repository.dart';
import 'package:vehicle_inspection/src/domain/services/connectivity_monitor.dart';
import 'package:vehicle_inspection/src/domain/services/photo_service.dart';
import 'package:vehicle_inspection/src/sync/sync_scheduler.dart';

/// Opens a throwaway SQLite database backed by the FFI factory, so the real
/// schema, foreign keys and triggers are exercised rather than mocked away.
AppDatabase openTestDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
    factoryOverride: databaseFactoryFfi,
    pathOverride: inMemoryDatabasePath,
  );
}

const Evaluator testEvaluator = Evaluator(
  id: 'ev-1',
  name: 'Ahmed Tariq',
  email: 'evaluator@test.com',
);

const Vehicle testVehicle = Vehicle(
  registrationNumber: 'ABC-123',
  make: 'Toyota',
  model: 'Corolla',
  manufacturingYear: 2019,
  vin: 'JTDBR32E720123456',
  mileageKm: 84500,
);

/// A small template with a known shape:
/// * `p1` and `p2` are required
/// * `p3` is optional
/// * `p4` is required and demands a photo when failed
InspectionTemplate buildTestTemplate({int version = 1}) {
  return InspectionTemplate(
    id: 'test-template',
    name: 'Test Checklist',
    version: version,
    isDefault: true,
    categories: [
      const InspectionCategory(
        id: 'cat-a',
        code: 'A',
        title: 'Category A',
        sortOrder: 1,
        points: [
          InspectionPoint(
            id: 'p1',
            categoryId: 'cat-a',
            code: 'A-01',
            title: 'Point one',
          ),
          InspectionPoint(
            id: 'p2',
            categoryId: 'cat-a',
            code: 'A-02',
            title: 'Point two',
          ),
        ],
      ),
      const InspectionCategory(
        id: 'cat-b',
        code: 'B',
        title: 'Category B',
        sortOrder: 2,
        points: [
          InspectionPoint(
            id: 'p3',
            categoryId: 'cat-b',
            code: 'B-01',
            title: 'Optional point',
            isRequired: false,
          ),
          InspectionPoint(
            id: 'p4',
            categoryId: 'cat-b',
            code: 'B-02',
            title: 'Needs evidence',
            requiresPhotoOnFail: true,
          ),
        ],
      ),
    ],
  );
}

/// Serves one fixed template without touching assets or the network.
class FakeTemplateRepository implements TemplateRepository {
  FakeTemplateRepository(this.template);

  final InspectionTemplate template;

  @override
  Future<InspectionTemplate> getActiveTemplate() async => template;

  @override
  Future<List<InspectionTemplate>> getTemplates() async => [template];

  @override
  Future<InspectionTemplate?> getTemplate(String id, {int? version}) async {
    if (id != template.id) return null;
    if (version != null && version != template.version) return null;
    return template;
  }

  @override
  Future<bool> refreshFromRemote() async => false;
}

/// Writes real (tiny) files so `File` operations in the repository behave as
/// they do on a device.
class FakePhotoService implements PhotoService {
  FakePhotoService();

  final List<String> deletedPaths = [];
  final Directory _root = Directory.systemTemp.createTempSync('vi_photos');

  /// Set to make the next capture behave as a cancelled picker.
  bool cancelNextCapture = false;

  int _counter = 0;

  @override
  Future<CapturedPhoto?> capture({
    required PhotoSource source,
    required String inspectionId,
  }) async {
    if (cancelNextCapture) {
      cancelNextCapture = false;
      return null;
    }
    _counter++;
    final file = File('${_root.path}/$inspectionId-$_counter.jpg')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    return CapturedPhoto(
      path: file.path,
      byteSize: file.lengthSync(),
      width: 1600,
      height: 1200,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    deletedPaths.add(path);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> deleteInspectionFiles(String inspectionId) async {}
}

/// Records sync requests instead of performing them.
class RecordingSyncScheduler implements SyncScheduler {
  final List<String> reasons = [];

  @override
  void requestSync({String reason = 'unspecified'}) => reasons.add(reason);
}

/// Connectivity the test drives directly.
class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({bool online = true}) : _online = online;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _online;

  bool get online => _online;

  set online(bool value) {
    _online = value;
    _controller.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<void> dispose() async => _controller.close();
}

/// Scriptable stand-in for the transport layer.
class FakeApiClient implements ApiClient {
  /// When true, every call fails as if the device had no route to the host.
  bool offline = false;

  /// Number of calls that should fail with a retryable 503 before succeeding.
  int failuresRemaining = 0;

  /// When set, calls fail with this status code instead of succeeding.
  int? permanentFailureStatus;

  final List<String> submittedInspections = [];
  final List<String> uploadedPhotos = [];
  String? authToken;

  int _sequence = 0;

  @override
  void setAuthToken(String? token) => authToken = token;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    _guard();
    return {'templates': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _guard();
    final id = body?['id'] as String? ?? '';
    submittedInspections.add(id);
    _sequence++;
    return {'id': 'srv-$_sequence', 'status': 'accepted'};
  }

  @override
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    Map<String, String>? fields,
  }) async {
    _guard();
    final photoId = fields?['photoId'] ?? 'unknown';
    uploadedPhotos.add(photoId);
    return {'id': photoId, 'url': 'https://cdn.test/$photoId.jpg'};
  }

  void _guard() {
    if (offline) throw const OfflineException();
    if (permanentFailureStatus != null) {
      throw ApiException('rejected', statusCode: permanentFailureStatus);
    }
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const ApiException('temporarily unavailable', statusCode: 503);
    }
  }
}
