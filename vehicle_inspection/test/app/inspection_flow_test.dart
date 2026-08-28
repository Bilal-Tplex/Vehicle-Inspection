import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_inspection/src/app/app.dart';
import 'package:vehicle_inspection/src/app/providers.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_template.dart';
import 'package:vehicle_inspection/src/sync/sync_state.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/fixtures.dart';

/// Drives the real app widget tree.
///
/// Everything below the repository line is replaced with in-memory fakes (see
/// `fake_repositories.dart` for why), but every screen, controller, route and
/// the grading service are the production ones. These tests answer the question
/// the unit tests cannot: does the UI actually build, navigate and validate?
void main() {
  late FakeInspectionRepository inspections;
  late FakeAuthRepository auth;
  late InspectionTemplate template;

  setUp(() {
    template = buildTestTemplate();
    inspections = FakeInspectionRepository(template);
    auth = FakeAuthRepository();
  });

  tearDown(() async {
    await inspections.dispose();
  });

  Widget buildApp({SyncState syncState = const SyncState()}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => auth),
        inspectionRepositoryProvider.overrideWith((ref) => inspections),
        templateRepositoryProvider
            .overrideWith((ref) => FakeTemplateRepository(template)),
        // Startup opens the database and starts the sync engine; both are
        // stubbed out here so the tree renders without touching either.
        appStartupProvider.overrideWith((ref) async {}),
        syncStateProvider.overrideWith((ref) => Stream.value(syncState)),
      ],
      child: const VehicleInspectionApp(),
    );
  }

  /// Pumps the app on a tall viewport.
  ///
  /// The default 800x600 test surface clips a checklist to its first couple of
  /// points, which would make these tests about scrolling rather than about
  /// behaviour. A tall window keeps every tile laid out and tappable.
  Future<void> pumpApp(WidgetTester tester, {SyncState? syncState}) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      syncState == null ? buildApp() : buildApp(syncState: syncState),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, {SyncState? syncState}) async {
    await pumpApp(tester, syncState: syncState);

    await tester.tap(find.text('Use test credentials'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> fillVehicleForm(WidgetTester tester) async {
    Future<void> type(String label, String value) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, label),
        value,
      );
    }

    await type('Registration number', 'ABC-123');
    await type('Make', 'Toyota');
    await type('Model', 'Corolla');
    await type('Year', '2019');
    await type('Mileage', '84500');
    await type('VIN / chassis number', 'JTDBR32E720123456');
    await tester.pumpAndSettle();
  }

  /// Taps [status] on every checklist tile currently in the tree.
  Future<void> answerEveryPoint(WidgetTester tester, String status) async {
    // Iterating backwards keeps earlier finders valid as the list rebuilds.
    for (var i = find.text(status).evaluate().length - 1; i >= 0; i--) {
      await tester.tap(find.text(status).at(i));
      await tester.pumpAndSettle();
    }
  }

  group('authentication', () {
    testWidgets('signing in lands on the dashboard with the evaluator name',
        (tester) async {
      await signIn(tester);

      expect(find.text('Ahmed Tariq'), findsOneWidget);
      expect(find.text('New Inspection'), findsWidgets);
      expect(find.text('My Inspections'), findsOneWidget);
    });

    testWidgets('a wrong password reports inline and stays put', (tester) async {
      await pumpApp(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'evaluator@test.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('a malformed email is caught before any request', (tester) async {
      await pumpApp(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });

  group('creating an inspection', () {
    testWidgets('an empty form is rejected without navigating', (tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();

      expect(find.text('Registration number is required.'), findsOneWidget);
      expect(find.text('VIN / chassis number is required.'), findsOneWidget);
      expect(find.text('Start checklist'), findsOneWidget);
      expect(inspections.store, isEmpty);
    });

    testWidgets('a short VIN is rejected', (tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();

      await fillVehicleForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'VIN / chassis number'),
        'TOOSHORT',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();

      expect(find.textContaining('VIN must be 17 characters'), findsOneWidget);
      expect(inspections.store, isEmpty);
    });
  });

  group('the checklist', () {
    Future<void> openChecklist(WidgetTester tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();
      await fillVehicleForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders entirely from template data', (tester) async {
      await openChecklist(tester);

      expect(find.text('ABC-123'), findsOneWidget);
      expect(find.text('Category A'), findsOneWidget);
      expect(find.text('Category B'), findsOneWidget);
      expect(find.text('Point one'), findsOneWidget);
      expect(find.text('A-01'), findsOneWidget);
      // The optional point is labelled as such, straight from the template.
      expect(find.text('Optional'), findsOneWidget);
      expect(find.textContaining('0/4 completed'), findsOneWidget);
    });

    testWidgets('answering updates progress and the live score', (tester) async {
      await openChecklist(tester);

      await tester.tap(find.text('Pass').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('1/4 completed'), findsOneWidget);
      expect(find.text('100.0%'), findsWidgets);

      await tester.tap(find.text('Fail').first);
      await tester.pumpAndSettle();

      // One point answered, and it failed: 0 of 2 possible.
      expect(find.text('0.0%'), findsWidgets);
    });

    testWidgets('blocks review while required points are unanswered',
        (tester) async {
      await openChecklist(tester);

      expect(
        find.textContaining('required points still need an answer'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Review & submit'));
      await tester.pumpAndSettle();

      // Still on the checklist, now filtered to what is missing.
      expect(find.text('Inspection summary'), findsNothing);
      expect(find.textContaining('0/4 completed'), findsOneWidget);
    });
  });

  group('submission', () {
    Future<void> completeAndReview(WidgetTester tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();
      await fillVehicleForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();
      await answerEveryPoint(tester, 'Pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Review & submit'));
      await tester.pumpAndSettle();
    }

    testWidgets('the summary shows the vehicle, breakdown and grade',
        (tester) async {
      await completeAndReview(tester);

      expect(find.text('Inspection summary'), findsOneWidget);
      expect(find.text('JTDBR32E720123456'), findsOneWidget);
      expect(find.text('Toyota Corolla'), findsWidgets);
      expect(find.text('84,500 km'), findsOneWidget);
      expect(find.text('No issues recorded'), findsOneWidget);
      expect(find.text('100.0%'), findsWidgets);
    });

    testWidgets('submitting produces an ID, a grade and a sync status',
        (tester) async {
      await completeAndReview(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit inspection'));
      await tester.pumpAndSettle();

      expect(find.text('Inspection submitted'), findsOneWidget);
      expect(find.textContaining('INS-'), findsWidgets);
      expect(find.text('Pending sync'), findsWidgets);
      // Saved locally and honest about not having reached the server yet.
      expect(
        find.textContaining('will upload automatically'),
        findsOneWidget,
      );
      expect(inspections.store.values.single.isSubmitted, isTrue);
      expect(inspections.store.values.single.gradeCode, 'A');
    });
  });

  group('history', () {
    testWidgets('a submitted inspection appears and opens read-only',
        (tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'New Inspection'));
      await tester.pumpAndSettle();
      await fillVehicleForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start checklist'));
      await tester.pumpAndSettle();
      await answerEveryPoint(tester, 'Pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Review & submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit inspection'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'My Inspections'));
      await tester.pumpAndSettle();

      expect(find.text('ABC-123'), findsWidgets);
      expect(find.text('Toyota Corolla'), findsWidgets);

      await tester.tap(find.text('ABC-123').first);
      await tester.pumpAndSettle();

      // The detail screen adds a sync card and hides every edit affordance.
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Retry sync now'), findsOneWidget);
      expect(find.text('Submit inspection'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
    });

    testWidgets('the empty state offers a way to start one', (tester) async {
      await signIn(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'My Inspections'));
      await tester.pumpAndSettle();

      expect(find.text('No inspections yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'New Inspection'), findsWidgets);
    });
  });

  group('sync banner', () {
    testWidgets('stays out of the way when everything is synced',
        (tester) async {
      await signIn(tester);

      expect(find.text('All inspections synced'), findsOneWidget);
    });

    testWidgets('reports pending work while offline', (tester) async {
      await signIn(
        tester,
        syncState: const SyncState(
          phase: SyncPhase.waitingForConnection,
          isOnline: false,
          pendingTasks: 3,
        ),
      );

      expect(
        find.textContaining('3 pending - will sync when back online'),
        findsOneWidget,
      );
    });
  });
}
