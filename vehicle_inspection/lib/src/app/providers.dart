import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants/app_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/app_logger.dart';
import '../data/local/app_database.dart';
import '../data/local/daos/inspection_dao.dart';
import '../data/local/daos/sync_queue_dao.dart';
import '../data/local/daos/template_dao.dart';
import '../data/local/session_store.dart';
import '../data/remote/auth_api.dart';
import '../data/remote/http_api_client.dart';
import '../data/remote/inspection_api.dart';
import '../data/remote/mock/mock_api_client.dart';
import '../data/remote/mock/network_simulator.dart';
import '../data/remote/template_api.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/inspection_repository_impl.dart';
import '../data/repositories/template_repository_impl.dart';
import '../data/services/connectivity_monitor_impl.dart';
import '../data/services/photo_service_impl.dart';
import '../domain/entities/inspection_summary.dart';
import '../domain/entities/inspection_template.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/inspection_repository.dart';
import '../domain/repositories/template_repository.dart';
import '../domain/services/connectivity_monitor.dart';
import '../domain/services/photo_service.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_scheduler.dart';
import '../sync/sync_state.dart';

/// Composition root.
///
/// Every dependency is declared once, here, and every consumer receives it
/// through an interface. Swapping the mock backend for a real one, or the
/// platform photo picker for a fake in a widget test, is a single override —
/// no class below this file knows which implementation it is talking to.

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// Developer-facing network switches. Not wired up in a production flavour.
final networkSimulatorProvider = Provider<NetworkSimulator>((ref) {
  final simulator = NetworkSimulator();
  ref.onDispose(simulator.dispose);
  return simulator;
});

/// The transport.
///
/// This is the only place that knows whether the app is talking to a real
/// server or the in-app fake. Everything above it depends on [ApiClient], so
/// the switch costs one branch and nothing else in the codebase changes.
final apiClientProvider = Provider<ApiClient>((ref) {
  if (AppConstants.useMockApi) {
    return MockApiClient(simulator: ref.watch(networkSimulatorProvider));
  }
  final client = HttpApiClient();
  ref.onDispose(client.dispose);
  return client;
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final inspectionDaoProvider = Provider<InspectionDao>((ref) {
  final dao = InspectionDao(ref.watch(appDatabaseProvider));
  ref.onDispose(dao.dispose);
  return dao;
});

final templateDaoProvider = Provider<TemplateDao>(
  (ref) => TemplateDao(ref.watch(appDatabaseProvider)),
);

final syncQueueDaoProvider = Provider<SyncQueueDao>(
  (ref) => SyncQueueDao(ref.watch(appDatabaseProvider)),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    // Back the token with EncryptedSharedPreferences rather than the plain
    // store, since inspector handsets are shared, field-used devices.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(secureStorageProvider)),
);

final connectivityMonitorProvider = Provider<ConnectivityMonitor>((ref) {
  final monitor = ConnectivityMonitorImpl(
    connectivity: Connectivity(),
    simulator: ref.watch(networkSimulatorProvider),
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});

final photoServiceProvider = Provider<PhotoService>(
  (ref) => PhotoServiceImpl(),
);

// ---------------------------------------------------------------------------
// Remote APIs
// ---------------------------------------------------------------------------

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final inspectionApiProvider = Provider<InspectionApi>(
  (ref) => InspectionApi(ref.watch(apiClientProvider)),
);

final templateApiProvider = Provider<TemplateApi>(
  (ref) => TemplateApi(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    queueDao: ref.watch(syncQueueDaoProvider),
    inspectionDao: ref.watch(inspectionDaoProvider),
    api: ref.watch(inspectionApiProvider),
    connectivity: ref.watch(connectivityMonitorProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// The narrow view of the engine that the repository depends on, which keeps
/// the dependency one-directional.
final syncSchedulerProvider = Provider<SyncScheduler>(
  (ref) => ref.watch(syncEngineProvider),
);

/// Live sync status for the banner and the per-row chips.
final syncStateProvider = StreamProvider<SyncState>(
  (ref) => ref.watch(syncEngineProvider).states,
);

/// Whether the device currently has a usable connection.
final connectivityStatusProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectivityMonitorProvider).onConnectivityChanged,
);

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    api: ref.watch(authApiProvider),
    sessionStore: ref.watch(sessionStoreProvider),
    apiClient: ref.watch(apiClientProvider),
  ),
);

final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => TemplateRepositoryImpl(
    dao: ref.watch(templateDaoProvider),
    api: ref.watch(templateApiProvider),
  ),
);

final inspectionRepositoryProvider = Provider<InspectionRepository>((ref) {
  return InspectionRepositoryImpl(
    inspectionDao: ref.watch(inspectionDaoProvider),
    syncQueueDao: ref.watch(syncQueueDaoProvider),
    templateRepository: ref.watch(templateRepositoryProvider),
    photoService: ref.watch(photoServiceProvider),
    syncScheduler: ref.watch(syncSchedulerProvider),
  );
});

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

/// The checklist new inspections are created from.
final activeTemplateProvider = FutureProvider<InspectionTemplate>(
  (ref) => ref.watch(templateRepositoryProvider).getActiveTemplate(),
);

/// Every inspection on the device, refreshed on any change.
final inspectionSummariesProvider = StreamProvider<List<InspectionSummary>>(
  (ref) => ref.watch(inspectionRepositoryProvider).watchSummaries(),
);

/// Dashboard counters, recomputed whenever inspections change.
///
/// `asyncMap` rather than an `async*` loop so the subscription tears down the
/// moment the screen goes away, instead of waiting for the next change.
final dashboardStatsProvider = StreamProvider<DashboardStats>((ref) {
  final repository = ref.watch(inspectionRepositoryProvider);
  return repository
      .watchSummaries()
      .asyncMap((_) => repository.fetchDashboardStats());
});

/// Light / dark / follow-system.
///
/// Kept in memory for this build; persisting it is a `SharedPreferences` write
/// away and does not affect anything else.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// One-time work needed before the first screen can be shown.
///
/// Seeding the checklist here — rather than lazily on the New Inspection
/// screen — means the very first inspection an evaluator starts is instant and
/// works with no connection.
final appStartupProvider = FutureProvider<void>((ref) async {
  final templates = ref.watch(templateRepositoryProvider);
  await templates.getActiveTemplate();
  await ref.watch(syncEngineProvider).start();

  // Pull any checklist the admin dashboard has published since last launch.
  // Deliberately not awaited: a slow or unreachable server must not delay the
  // first screen, and the seeded template is already usable.
  unawaited(
    templates.refreshFromRemote().then((changed) {
      if (changed) {
        AppLogger.info('Newer template pulled from the backend', scope: 'template');
        ref.invalidate(activeTemplateProvider);
      }
    }),
  );
});

/// Pulls newer checklist versions on demand, for the Settings screen.
///
/// Returns `true` when something changed, so the caller can tell the evaluator
/// whether the trip was worth it.
final templateRefreshProvider = FutureProvider.autoDispose<bool>((ref) async {
  final changed = await ref.watch(templateRepositoryProvider).refreshFromRemote();
  if (changed) ref.invalidate(activeTemplateProvider);
  return changed;
});
