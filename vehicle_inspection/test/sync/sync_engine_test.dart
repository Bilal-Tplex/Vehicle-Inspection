import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_inspection/src/data/local/app_database.dart';
import 'package:vehicle_inspection/src/data/local/daos/inspection_dao.dart';
import 'package:vehicle_inspection/src/data/local/daos/sync_queue_dao.dart';
import 'package:vehicle_inspection/src/data/remote/inspection_api.dart';
import 'package:vehicle_inspection/src/data/repositories/inspection_repository_impl.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_template.dart';
import 'package:vehicle_inspection/src/domain/entities/item_status.dart';
import 'package:vehicle_inspection/src/domain/entities/sync_status.dart';
import 'package:vehicle_inspection/src/domain/services/photo_service.dart';
import 'package:vehicle_inspection/src/sync/sync_engine.dart';
import 'package:vehicle_inspection/src/sync/sync_state.dart';
import 'package:vehicle_inspection/src/sync/sync_task.dart';

import '../helpers/fixtures.dart';

void main() {
  late AppDatabase database;
  late InspectionDao inspectionDao;
  late SyncQueueDao queueDao;
  late FakeApiClient apiClient;
  late FakeConnectivityMonitor connectivity;
  late SyncEngine engine;
  late InspectionRepositoryImpl repository;
  late InspectionTemplate template;

  setUp(() {
    database = openTestDatabase();
    inspectionDao = InspectionDao(database);
    queueDao = SyncQueueDao(database);
    apiClient = FakeApiClient();
    connectivity = FakeConnectivityMonitor();
    template = buildTestTemplate();

    engine = SyncEngine(
      queueDao: queueDao,
      inspectionDao: inspectionDao,
      api: InspectionApi(apiClient),
      connectivity: connectivity,
      debounce: Duration.zero,
    );

    repository = InspectionRepositoryImpl(
      inspectionDao: inspectionDao,
      syncQueueDao: queueDao,
      templateRepository: FakeTemplateRepository(template),
      photoService: FakePhotoService(),
      // The engine is driven explicitly via syncNow() in these tests, so the
      // repository gets an inert scheduler rather than a debounce timer that
      // would fire after the database is closed.
      syncScheduler: RecordingSyncScheduler(),
    );
  });

  tearDown(() async {
    await inspectionDao.dispose();
    await engine.dispose();
    await connectivity.dispose();
    await database.close();
  });

  /// Creates a submittable inspection, optionally with photos attached.
  Future<Inspection> submitInspection({int photos = 0}) async {
    final inspection = await repository.createDraft(
      vehicle: testVehicle,
      evaluator: testEvaluator,
      template: template,
    );
    for (final pointId in ['p1', 'p2', 'p4']) {
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: pointId,
        status: ItemStatus.pass,
      );
    }
    for (var i = 0; i < photos; i++) {
      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );
    }
    return repository.submit(inspectionId: inspection.id, template: template);
  }

  group('offline', () {
    test('submission succeeds and the work waits in the queue', () async {
      connectivity.online = false;
      apiClient.offline = true;

      final submitted = await submitInspection(photos: 2);

      expect(submitted.status, InspectionStatus.submitted);
      expect(await queueDao.countPending(), 3);

      await engine.syncNow();

      expect(apiClient.submittedInspections, isEmpty);
      expect(await queueDao.countPending(), 3);
      expect(engine.state.phase, SyncPhase.waitingForConnection);
    });

    test('nothing is lost: the record is intact and readable offline',
        () async {
      connectivity.online = false;
      apiClient.offline = true;

      final submitted = await submitInspection(photos: 1);
      await engine.syncNow();

      final reloaded = await repository.findById(submitted.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.gradeCode, isNotNull);
      expect(reloaded.allPhotos, hasLength(1));
      expect(reloaded.syncStatus, SyncStatus.pending);
    });

    test('coming back online drains everything', () async {
      connectivity.online = false;
      apiClient.offline = true;
      final submitted = await submitInspection(photos: 2);
      await engine.syncNow();

      connectivity.online = true;
      apiClient.offline = false;
      await engine.syncNow();

      final synced = await repository.findById(submitted.id);
      expect(synced!.remoteId, isNotNull);
      expect(synced.syncStatus, SyncStatus.synced);
      expect(apiClient.uploadedPhotos, hasLength(2));
      expect(await queueDao.countPending(), 0);
      expect(engine.state.phase, SyncPhase.idle);
    });
  });

  group('online', () {
    test('submits the inspection and uploads its photos', () async {
      final submitted = await submitInspection(photos: 2);

      await engine.syncNow();

      expect(apiClient.submittedInspections, [submitted.id]);
      expect(apiClient.uploadedPhotos, hasLength(2));

      final synced = await repository.findById(submitted.id);
      expect(synced!.syncStatus, SyncStatus.synced);
      expect(
        synced.allPhotos.every((p) => p.syncStatus == SyncStatus.synced),
        isTrue,
      );
      expect(synced.allPhotos.every((p) => p.remoteUrl != null), isTrue);
    });

    test('stays pending until the last photo has landed', () async {
      final submitted = await submitInspection(photos: 1);

      // Let the inspection through but fail the photo upload.
      apiClient.failuresRemaining = 0;
      await engine.syncNow();
      expect(
        (await repository.findById(submitted.id))!.syncStatus,
        SyncStatus.synced,
      );

      // A second inspection where the photo cannot upload yet.
      apiClient.offline = false;
      final other = await submitInspection(photos: 1);
      apiClient.permanentFailureStatus = 503;
      await engine.syncNow();
      apiClient.permanentFailureStatus = null;

      final partial = await repository.findById(other.id);
      expect(partial!.syncStatus, isNot(SyncStatus.synced));
    });

    test('an inspection already accepted is not submitted twice', () async {
      final submitted = await submitInspection();
      await engine.syncNow();
      expect(apiClient.submittedInspections, hasLength(1));

      // Re-queue the same work, as a manual retry would.
      await repository.retrySync(submitted.id);
      await engine.syncNow();

      expect(apiClient.submittedInspections, hasLength(1));
    });
  });

  group('failure handling', () {
    test('a retryable error keeps the task queued and backs it off', () async {
      await submitInspection();
      apiClient.failuresRemaining = 1;

      await engine.syncNow();

      // Still queued, but not due again yet.
      expect(await queueDao.countPending(), 1);
      expect(await queueDao.findDue(), isEmpty);

      final task = (await queueDao.findAll()).single;
      expect(task.attempts, 1);
      expect(task.lastError, isNotNull);
      expect(task.nextAttemptAt.isAfter(DateTime.now()), isTrue);
    });

    test('the task succeeds once its backoff window has passed', () async {
      final submitted = await submitInspection();
      apiClient.failuresRemaining = 1;
      await engine.syncNow();

      // Simulate the wait rather than actually sleeping for it.
      await queueDao.reschedule(submitted.id);
      await engine.syncNow();

      expect(apiClient.submittedInspections, hasLength(1));
      expect(await queueDao.countPending(), 0);
      expect(
        (await repository.findById(submitted.id))!.syncStatus,
        SyncStatus.synced,
      );
    });

    test('a non-retryable rejection fails immediately instead of looping',
        () async {
      final submitted = await submitInspection();
      // 422 means the payload is wrong; resending it cannot help.
      apiClient.permanentFailureStatus = 422;

      await engine.syncNow();

      expect(await queueDao.countPending(), 0);
      final failed = await repository.findById(submitted.id);
      expect(failed!.syncStatus, SyncStatus.failed);
      expect(failed.lastSyncError, isNotNull);
      expect(engine.state.phase, SyncPhase.failed);
    });

    test('a failed inspection can be retried manually', () async {
      final submitted = await submitInspection();
      apiClient.permanentFailureStatus = 422;
      await engine.syncNow();
      expect(
        (await repository.findById(submitted.id))!.syncStatus,
        SyncStatus.failed,
      );

      apiClient.permanentFailureStatus = null;
      await repository.retrySync(submitted.id);
      await engine.syncNow();

      final recovered = await repository.findById(submitted.id);
      expect(recovered!.syncStatus, SyncStatus.synced);
      expect(recovered.remoteId, isNotNull);
    });

    test('a photo whose inspection is not accepted yet is deferred, not failed',
        () async {
      connectivity.online = false;
      apiClient.offline = true;
      final submitted = await submitInspection(photos: 1);
      await engine.syncNow();

      // Drop the inspection task so only the photo is due. Its parent has no
      // remote id, so the upload cannot proceed.
      final inspectionTask = (await queueDao.findAll())
          .firstWhere((t) => t.operation == SyncOperation.submitInspection);
      await queueDao.remove(inspectionTask.id!);

      connectivity.online = true;
      apiClient.offline = false;
      await engine.syncNow();

      // Still queued, no upload attempted, and no retry budget consumed.
      expect(apiClient.uploadedPhotos, isEmpty);
      expect(await queueDao.countPending(), 1);
      expect((await queueDao.findAll()).single.attempts, 0);
      expect(engine.state.phase, isNot(SyncPhase.failed));

      final unchanged = await repository.findById(submitted.id);
      expect(unchanged!.syncStatus, isNot(SyncStatus.failed));
    });

    test('an inspection deleted while queued does not wedge the queue',
        () async {
      final submitted = await submitInspection();
      await inspectionDao.delete(submitted.id);
      // Re-queue by hand: deleting through the repository would clear it.
      await queueDao.enqueue(
        entityType: SyncEntityType.inspection,
        entityId: submitted.id,
        operation: SyncOperation.submitInspection,
      );

      await engine.syncNow();

      expect(await queueDao.countPending(), 0);
    });
  });

  group('state reporting', () {
    test('reports progress through a run', () async {
      await submitInspection(photos: 2);

      final phases = <SyncPhase>[];
      final subscription = engine.states.listen((s) => phases.add(s.phase));

      await engine.syncNow();
      // The controller delivers asynchronously, so give the last event a turn
      // of the event loop before tearing the listener down.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(phases, contains(SyncPhase.syncing));
      expect(phases.last, SyncPhase.idle);
      expect(engine.state.phase, SyncPhase.idle);
      expect(engine.state.lastSyncedAt, isNotNull);
    });

    test('a completed upload refreshes anything watching the history list',
        () async {
      // Regression guard: the engine writes through the DAO, not the
      // repository, so if the change signal lived on the repository a synced
      // record would keep rendering as "Pending sync".
      connectivity.online = false;
      apiClient.offline = true;
      await submitInspection();

      final statuses = <SyncStatus>[];
      final subscription = repository.watchSummaries().listen((summaries) {
        if (summaries.isNotEmpty) statuses.add(summaries.single.syncStatus);
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      connectivity.online = true;
      apiClient.offline = false;
      await engine.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(statuses.first, SyncStatus.pending);
      expect(statuses.last, SyncStatus.synced);
    });

    test('counts everything still queued', () async {
      connectivity.online = false;
      apiClient.offline = true;
      await submitInspection(photos: 3);

      await engine.syncNow();

      expect(engine.state.pendingTasks, 4);
      expect(engine.state.hasPendingWork, isTrue);
      expect(engine.state.message, contains('4 pending'));
    });
  });
}
