import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vehicle_inspection/src/app/app.dart';
import 'package:vehicle_inspection/src/app/providers.dart';
import 'package:vehicle_inspection/src/data/remote/mock/mock_api_client.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection.dart';
import 'package:vehicle_inspection/src/domain/entities/item_status.dart';
import 'package:vehicle_inspection/src/domain/entities/sync_status.dart';
import 'package:vehicle_inspection/src/domain/entities/vehicle.dart';
import 'package:vehicle_inspection/src/domain/services/photo_service.dart';

/// On-device tests.
///
/// These run against the real Android runtime, which is the only place the
/// parts the unit and widget suites cannot reach are actually exercised:
///
/// * **Real SQLite** — the schema, foreign keys, cascades and indexes as the
///   device creates them, not an in-memory FFI stand-in.
/// * **Real asset seeding** — the bundled 25-point checklist parsed out of the
///   APK and written into the database on first launch.
/// * **Real keystore** — `flutter_secure_storage` against Android's
///   EncryptedSharedPreferences.
/// * **Real plugin registration** — a missing platform channel shows up here
///   and nowhere else.
///
/// Only the photo service is stubbed, because a camera intent needs a human.
class RecordingPhotoService implements PhotoService {
  final List<String> captured = [];

  @override
  Future<CapturedPhoto?> capture({
    required PhotoSource source,
    required String inspectionId,
  }) async {
    // A real file on the device's filesystem, not a placeholder path. The
    // upload path stats the file before sending and rejects a missing one with
    // a non-retryable 400, so a fake path would exercise the failure branch
    // instead of the one we are trying to verify.
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/vi_${inspectionId}_${captured.length}.jpg',
    );
    await file.writeAsBytes(List<int>.filled(4096, 7), flush: true);
    captured.add(file.path);

    return CapturedPhoto(
      path: file.path,
      byteSize: await file.length(),
      width: 800,
      height: 600,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> deleteInspectionFiles(String inspectionId) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late RecordingPhotoService photoService;

  Future<void> launch(WidgetTester tester) async {
    photoService = RecordingPhotoService();
    container = ProviderContainer(
      overrides: [
        photoServiceProvider.overrideWith((ref) => photoService),
        // The app now points at a real backend by default. These tests assert
        // on-device storage and the sync pipeline, not the server, so they run
        // against the in-app mock to stay hermetic — otherwise a stopped
        // backend would look like a test failure.
        apiClientProvider.overrideWith(
          (ref) => MockApiClient(simulator: ref.watch(networkSimulatorProvider)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VehicleInspectionApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Clears any inspections a previous run left in the real database.
  Future<void> resetDatabase() async {
    await container.read(appDatabaseProvider).clearInspectionData();
  }

  Future<void> signIn(WidgetTester tester) async {
    // A previous run may have left a session in the keystore.
    if (find.text('Use test credentials').evaluate().isEmpty) return;

    await tester.tap(find.text('Use test credentials'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  group('on-device', () {
    testWidgets('boots, seeds the bundled checklist and signs in',
        (tester) async {
      await launch(tester);
      await signIn(tester);

      expect(find.text('Ahmed Tariq'), findsOneWidget);

      // The 25-point template was parsed from the APK asset and written to
      // SQLite, then read back through the DAO.
      final template =
          await container.read(templateRepositoryProvider).getActiveTemplate();
      expect(template.totalPointCount, 25);
      expect(template.categories, hasLength(5));
      expect(template.gradingRules.pointsFor(ItemStatus.pass), 2);

      // Round-tripping through the real database preserves the grading rules.
      final reloaded = await container
          .read(templateDaoProvider)
          .findById(template.id, version: template.version);
      expect(reloaded, isNotNull);
      expect(reloaded!.totalPointCount, 25);
      expect(reloaded.gradingRules.bandFor(85).code, 'B');
    });

    testWidgets('the session survives in the real keystore', (tester) async {
      await launch(tester);
      await signIn(tester);

      final restored =
          await container.read(authRepositoryProvider).restoreSession();
      expect(restored, isNotNull);
      expect(restored!.evaluator.email, 'evaluator@test.com');
      expect(restored.accessToken, isNotEmpty);
    });

    testWidgets('an inspection created through the UI lands in SQLite',
        (tester) async {
      await launch(tester);
      await signIn(tester);
      await resetDatabase();

      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();

      Future<void> type(String label, String value) async {
        await tester.enterText(
          find.widgetWithText(TextFormField, label),
          value,
        );
      }

      await type('Registration number', 'LEA-4021');
      await type('Make', 'Honda');
      await type('Model', 'Civic');
      await type('Year', '2020');
      await type('Mileage', '52300');
      await type('VIN / chassis number', 'JHMFA36266S000123');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();

      // Every category from the bundled template is on screen.
      expect(find.text('Exterior'), findsOneWidget);
      expect(find.textContaining('0/25 completed'), findsOneWidget);

      // And it is genuinely on disk: 25 item rows, written in one transaction.
      final summaries =
          await container.read(inspectionRepositoryProvider).fetchSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.registrationNumber, 'LEA-4021');
      expect(summaries.single.totalItems, 25);

      final stored = await container
          .read(inspectionRepositoryProvider)
          .findById(summaries.single.id);
      expect(stored!.items, hasLength(25));
      expect(stored.vehicle.vin, 'JHMFA36266S000123');
    });

    testWidgets('a full offline submission queues, then syncs on reconnect',
        (tester) async {
      await launch(tester);
      await signIn(tester);
      await resetDatabase();

      final repository = container.read(inspectionRepositoryProvider);
      final template =
          await container.read(templateRepositoryProvider).getActiveTemplate();
      final session =
          await container.read(authRepositoryProvider).restoreSession();

      // Simulate losing signal before any work is done.
      container.read(networkSimulatorProvider).setOffline(true);
      await tester.pumpAndSettle();

      var inspection = await repository.createDraft(
        vehicle: const Vehicle(
          registrationNumber: 'ABC-123',
          make: 'Toyota',
          model: 'Corolla',
          manufacturingYear: 2019,
          vin: 'JTDBR32E720123456',
          mileageKm: 84500,
        ),
        evaluator: session!.evaluator,
        template: template,
      );

      // Answer the whole 25-point checklist: 20 passes, 3 minor issues, 2 N/A.
      // Driving 25 tiles through the UI would test scrolling, not behaviour.
      final points = template.allPoints;
      for (var i = 0; i < points.length; i++) {
        final status = switch (i) {
          < 20 => ItemStatus.pass,
          < 23 => ItemStatus.minorIssue,
          _ => ItemStatus.notApplicable,
        };
        inspection = await repository.setItemStatus(
          inspectionId: inspection.id,
          pointId: points[i].id,
          status: status,
        );
      }

      await repository.attachPhoto(
        inspectionId: inspection.id,
        pointId: points.first.id,
        source: PhotoSource.camera,
      );

      final submitted = await repository.submit(
        inspectionId: inspection.id,
        template: template,
      );

      // 20 passes (40) + 3 minor (3) = 43 of 46 applicable points; N/A excluded.
      expect(submitted.obtainedPoints, 43);
      expect(submitted.maxPoints, 46);
      expect(submitted.gradeCode, 'A');
      expect(submitted.status, InspectionStatus.submitted);

      // Offline: accepted locally, nothing sent, work durably queued.
      expect(submitted.syncStatus, SyncStatus.pending);
      expect(submitted.remoteId, isNull);
      expect(await container.read(syncQueueDaoProvider).countPending(), 2);

      final engine = container.read(syncEngineProvider);
      await engine.syncNow();
      expect(
        (await repository.findById(submitted.id))!.remoteId,
        isNull,
        reason: 'still offline, so nothing should have reached the server',
      );

      // Reconnect and drain.
      container.read(networkSimulatorProvider).setOffline(false);
      await tester.pumpAndSettle();
      await engine.syncNow();

      final synced = await repository.findById(submitted.id);
      expect(synced!.remoteId, isNotNull);
      expect(synced.syncStatus, SyncStatus.synced);
      expect(
        synced.allPhotos.single.syncStatus,
        SyncStatus.synced,
        reason: 'the photo uploads on its own queued task',
      );
      expect(await container.read(syncQueueDaoProvider).countPending(), 0);
    });

    testWidgets('a submitted inspection reads back after a fresh launch',
        (tester) async {
      // Proves the data is on disk rather than in a warm cache: the previous
      // test's inspection is still here in a brand-new widget tree.
      await launch(tester);
      await signIn(tester);

      final summaries =
          await container.read(inspectionRepositoryProvider).fetchSummaries();
      expect(summaries, isNotEmpty);

      final latest = summaries.first;
      expect(latest.registrationNumber, 'ABC-123');
      expect(latest.gradeCode, 'A');
      expect(latest.syncStatus, SyncStatus.synced);
    });
  });
}
