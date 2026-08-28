import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_inspection/src/core/error/failures.dart';
import 'package:vehicle_inspection/src/data/local/app_database.dart';
import 'package:vehicle_inspection/src/data/local/daos/inspection_dao.dart';
import 'package:vehicle_inspection/src/data/local/daos/sync_queue_dao.dart';
import 'package:vehicle_inspection/src/data/repositories/inspection_repository_impl.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_summary.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_template.dart';
import 'package:vehicle_inspection/src/domain/entities/item_status.dart';
import 'package:vehicle_inspection/src/domain/entities/sync_status.dart';
import 'package:vehicle_inspection/src/domain/services/photo_service.dart';

import '../helpers/fixtures.dart';

void main() {
  late AppDatabase database;
  late InspectionDao inspectionDao;
  late SyncQueueDao queueDao;
  late FakePhotoService photoService;
  late RecordingSyncScheduler scheduler;
  late InspectionRepositoryImpl repository;
  late InspectionTemplate template;

  setUp(() {
    database = openTestDatabase();
    inspectionDao = InspectionDao(database);
    queueDao = SyncQueueDao(database);
    photoService = FakePhotoService();
    scheduler = RecordingSyncScheduler();
    template = buildTestTemplate();

    repository = InspectionRepositoryImpl(
      inspectionDao: inspectionDao,
      syncQueueDao: queueDao,
      templateRepository: FakeTemplateRepository(template),
      photoService: photoService,
      syncScheduler: scheduler,
    );
  });

  tearDown(() async {
    await inspectionDao.dispose();
    await database.close();
  });

  Future<Inspection> createDraft() => repository.createDraft(
        vehicle: testVehicle,
        evaluator: testEvaluator,
        template: template,
      );

  /// Answers every required point so the inspection is submittable.
  Future<void> completeRequiredPoints(String id) async {
    for (final pointId in ['p1', 'p2', 'p4']) {
      await repository.setItemStatus(
        inspectionId: id,
        pointId: pointId,
        status: ItemStatus.pass,
      );
    }
  }

  group('createDraft', () {
    test('creates one item per template point, all pending', () async {
      final inspection = await createDraft();

      expect(inspection.items, hasLength(template.totalPointCount));
      expect(
        inspection.items.every((item) => item.status == ItemStatus.pending),
        isTrue,
      );
      expect(inspection.completedItems, 0);
      expect(inspection.status, InspectionStatus.draft);
      expect(inspection.syncStatus, SyncStatus.draftLocal);
    });

    test('generates a quotable reference number without a server', () async {
      final inspection = await createDraft();

      expect(inspection.referenceNumber, startsWith('INS-'));
      expect(inspection.remoteId, isNull);
    });

    test('normalises registration and VIN so lookups are consistent', () async {
      final inspection = await repository.createDraft(
        vehicle: testVehicle.copyWith(
          registrationNumber: '  abc-123 ',
          vin: 'jtdbr32e720123456',
        ),
        evaluator: testEvaluator,
        template: template,
      );

      expect(inspection.vehicle.registrationNumber, 'ABC-123');
      expect(inspection.vehicle.vin, 'JTDBR32E720123456');
    });

    test('does not queue anything before submission', () async {
      await createDraft();
      expect(await queueDao.countPending(), 0);
    });

    test('survives a round trip through the database', () async {
      final created = await createDraft();
      final loaded = await repository.findById(created.id);

      expect(loaded, isNotNull);
      expect(loaded!.referenceNumber, created.referenceNumber);
      expect(loaded.items, hasLength(created.items.length));
      expect(loaded.vehicle.mileageKm, testVehicle.mileageKm);
    });
  });

  group('answering points', () {
    test('records the status and updates progress', () async {
      final inspection = await createDraft();

      final updated = await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p1',
        status: ItemStatus.minorIssue,
      );

      expect(updated.itemForPoint('p1')!.status, ItemStatus.minorIssue);
      expect(updated.completedItems, 1);
    });

    test('re-grades on every change so the live score is always current',
        () async {
      final inspection = await createDraft();

      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p1',
        status: ItemStatus.pass,
      );
      var summaries = await repository.fetchSummaries();
      expect(summaries.single.scorePercentage, 100);

      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p2',
        status: ItemStatus.fail,
      );
      summaries = await repository.fetchSummaries();
      expect(summaries.single.scorePercentage, 50);
    });

    test('stores and clears comments', () async {
      final inspection = await createDraft();

      var updated = await repository.setItemComment(
        inspectionId: inspection.id,
        pointId: 'p1',
        comment: '  Scratched near the door  ',
      );
      expect(updated.itemForPoint('p1')!.comment, 'Scratched near the door');

      updated = await repository.setItemComment(
        inspectionId: inspection.id,
        pointId: 'p1',
        comment: '   ',
      );
      expect(updated.itemForPoint('p1')!.hasComment, isFalse);
    });

    test('rejects a point that is not on the template', () async {
      final inspection = await createDraft();

      expect(
        () => repository.setItemStatus(
          inspectionId: inspection.id,
          pointId: 'does-not-exist',
          status: ItemStatus.pass,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('photos', () {
    test('attaches a photo to the right item', () async {
      final inspection = await createDraft();

      final updated = await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );

      final item = updated.itemForPoint('p1')!;
      expect(item.photos, hasLength(1));
      expect(item.photos.single.byteSize, greaterThan(0));
      expect(item.photos.single.syncStatus, SyncStatus.draftLocal);
    });

    test('a cancelled picker leaves the inspection untouched', () async {
      final inspection = await createDraft();
      photoService.cancelNextCapture = true;

      final updated = await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.gallery,
      );

      expect(updated.allPhotos, isEmpty);
    });

    test('enforces the per-point photo limit from the template', () async {
      final inspection = await createDraft();
      // The fixture leaves maxPhotos at its default of 3.
      for (var i = 0; i < 3; i++) {
        await repository.attachPhoto(
          inspectionId: inspection.id,
          pointId: 'p1',
          source: PhotoSource.camera,
        );
      }

      expect(
        () => repository.attachPhoto(
          inspectionId: inspection.id,
          pointId: 'p1',
          source: PhotoSource.camera,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('removing a photo deletes its row and its file', () async {
      final inspection = await createDraft();
      final withPhoto = await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );
      final photo = withPhoto.allPhotos.single;

      final updated = await repository.removePhoto(
        inspectionId: inspection.id,
        photoId: photo.id,
      );

      expect(updated.allPhotos, isEmpty);
      expect(photoService.deletedPaths, contains(photo.localPath));
    });

    test('replacing swaps the file but keeps the point at one photo', () async {
      final inspection = await createDraft();
      final withPhoto = await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );
      final original = withPhoto.allPhotos.single;

      final updated = await repository.replacePhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        photoId: original.id,
        source: PhotoSource.camera,
      );

      expect(updated.itemForPoint('p1')!.photos, hasLength(1));
      expect(updated.allPhotos.single.id, isNot(original.id));
      expect(photoService.deletedPaths, contains(original.localPath));
    });
  });

  group('submission', () {
    test('blocks while required points are unanswered', () async {
      final inspection = await createDraft();
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p1',
        status: ItemStatus.pass,
      );

      await expectLater(
        repository.submit(inspectionId: inspection.id, template: template),
        throwsA(isA<ValidationFailure>()),
      );
      // Nothing was queued by the failed attempt.
      expect(await queueDao.countPending(), 0);
    });

    test('optional points do not block submission', () async {
      final inspection = await createDraft();
      await completeRequiredPoints(inspection.id);

      final submitted = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      expect(submitted.status, InspectionStatus.submitted);
      expect(submitted.itemForPoint('p3')!.status, ItemStatus.pending);
    });

    test('blocks a failed point that owes a mandatory photo', () async {
      final inspection = await createDraft();
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p1',
        status: ItemStatus.pass,
      );
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p2',
        status: ItemStatus.pass,
      );
      // p4 requires a photo when failed.
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p4',
        status: ItemStatus.fail,
      );

      await expectLater(
        repository.submit(inspectionId: inspection.id, template: template),
        throwsA(isA<ValidationFailure>()),
      );

      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p4',
        source: PhotoSource.camera,
      );

      final submitted = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );
      expect(submitted.status, InspectionStatus.submitted);
    });

    test('stores the grade snapshot at submission', () async {
      final inspection = await createDraft();
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p1',
        status: ItemStatus.pass,
      );
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p2',
        status: ItemStatus.minorIssue,
      );
      await repository.setItemStatus(
        inspectionId: inspection.id,
        pointId: 'p4',
        status: ItemStatus.pass,
      );

      final submitted = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      // 2 + 1 + 2 = 5 of 6.
      expect(submitted.obtainedPoints, 5);
      expect(submitted.maxPoints, 6);
      expect(submitted.scorePercentage, closeTo(83.3, 0.1));
      expect(submitted.gradeCode, 'B');
      expect(submitted.submittedAt, isNotNull);
    });

    test('queues the inspection and each photo separately', () async {
      final inspection = await createDraft();
      await completeRequiredPoints(inspection.id);
      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );
      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p2',
        source: PhotoSource.camera,
      );

      await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      // One task for the inspection, one per photo.
      expect(await queueDao.countPending(), 3);
      expect(scheduler.reasons, contains('inspection submitted'));
    });

    test('marks the record pending sync rather than waiting for a server',
        () async {
      final inspection = await createDraft();
      await completeRequiredPoints(inspection.id);

      final submitted = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      expect(submitted.syncStatus, SyncStatus.pending);
      expect(submitted.remoteId, isNull);
    });

    test('a submitted inspection can no longer be edited', () async {
      final inspection = await createDraft();
      await completeRequiredPoints(inspection.id);
      await repository.submit(inspectionId: inspection.id, template: template);

      expect(
        () => repository.setItemStatus(
          inspectionId: inspection.id,
          pointId: 'p1',
          status: ItemStatus.fail,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('submitting twice is a no-op rather than a duplicate', () async {
      final inspection = await createDraft();
      await completeRequiredPoints(inspection.id);
      await repository.submit(inspectionId: inspection.id, template: template);

      final again = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      expect(again.status, InspectionStatus.submitted);
      expect(await queueDao.countPending(), 1);
    });
  });

  group('queries', () {
    test('dashboard counters separate drafts, completed and pending', () async {
      final draft = await createDraft();
      expect(draft, isNotNull);

      final second = await createDraft();
      await completeRequiredPoints(second.id);
      await repository.submit(inspectionId: second.id, template: template);

      final stats = await repository.fetchDashboardStats();
      expect(stats.draftCount, 1);
      expect(stats.completedCount, 1);
      expect(stats.pendingSyncCount, 1);
    });

    test('history filters by state', () async {
      final draft = await createDraft();
      final submitted = await createDraft();
      await completeRequiredPoints(submitted.id);
      await repository.submit(inspectionId: submitted.id, template: template);

      final drafts = await repository.fetchSummaries(
        filter: InspectionHistoryFilter.drafts,
      );
      expect(drafts.single.id, draft.id);

      final done = await repository.fetchSummaries(
        filter: InspectionHistoryFilter.submitted,
      );
      expect(done.single.id, submitted.id);

      final pending = await repository.fetchSummaries(
        filter: InspectionHistoryFilter.pendingSync,
      );
      expect(pending.single.id, submitted.id);
    });

    test('search matches registration, VIN and reference number', () async {
      final inspection = await createDraft();

      expect(await repository.fetchSummaries(query: 'ABC'), hasLength(1));
      expect(await repository.fetchSummaries(query: 'jtdbr'), hasLength(1));
      expect(
        await repository.fetchSummaries(query: inspection.referenceNumber),
        hasLength(1),
      );
      expect(await repository.fetchSummaries(query: 'XYZ-999'), isEmpty);
    });

    test('watchSummaries emits immediately and again after every change',
        () async {
      final emissions = <int>[];
      final subscription = repository
          .watchSummaries()
          .listen((summaries) => emissions.add(summaries.length));

      // Let the initial snapshot land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await createDraft();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await subscription.cancel();
      expect(emissions.first, 0);
      expect(emissions.last, 1);
    });

    test('deleting a draft removes its items and photos', () async {
      final inspection = await createDraft();
      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: 'p1',
        source: PhotoSource.camera,
      );

      await repository.delete(inspection.id);

      expect(await repository.findById(inspection.id), isNull);
      expect(await inspectionDao.findPhotoPaths(inspection.id), isEmpty);
    });
  });
}
