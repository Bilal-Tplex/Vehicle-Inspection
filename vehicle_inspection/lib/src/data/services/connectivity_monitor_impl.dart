import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/services/connectivity_monitor.dart';
import '../remote/mock/network_simulator.dart';

/// Connectivity backed by the platform, with the developer override folded in.
///
/// Two things can put the app "offline": the radio, and the simulated-offline
/// switch on the Settings screen. Combining them here means every consumer —
/// the sync engine, the offline banner, the submit button — agrees on one
/// answer instead of each checking a different source.
///
/// Note the deliberate limit: the platform reporting an active interface is not
/// proof the API is reachable (captive portals, dead backhaul). The sync engine
/// therefore treats this as a hint and still handles request failures.
class ConnectivityMonitorImpl implements ConnectivityMonitor {
  ConnectivityMonitorImpl({
    required Connectivity connectivity,
    NetworkSimulator? simulator,
  })  : _connectivity = connectivity,
        _simulator = simulator {
    _controller = StreamController<bool>.broadcast(
      // Replay the last known value so a late subscriber is never stuck at
      // "unknown" until the next transition.
      onListen: () => _emit(_lastKnown),
    );
    _simulator?.addListener(_onSimulatorChanged);
    _subscription =
        _connectivity.onConnectivityChanged.listen(_onPlatformChanged);
    unawaited(_primeInitialState());
  }

  final Connectivity _connectivity;
  final NetworkSimulator? _simulator;

  late final StreamController<bool> _controller;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _platformOnline = true;
  bool _lastKnown = true;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<bool> isOnline() async {
    if (_simulator?.isOffline ?? false) return false;
    try {
      final results = await _connectivity.checkConnectivity();
      _platformOnline = _hasConnection(results);
    } catch (error) {
      // If the platform channel misbehaves, assume online and let the actual
      // request decide. Guessing "offline" would stall the queue for no reason.
      AppLogger.warn('Connectivity check failed', scope: 'net', error: error);
      _platformOnline = true;
    }
    return _resolve();
  }

  Future<void> _primeInitialState() async {
    final online = await isOnline();
    _emit(online);
  }

  void _onPlatformChanged(List<ConnectivityResult> results) {
    _platformOnline = _hasConnection(results);
    _emit(_resolve());
  }

  void _onSimulatorChanged() => _emit(_resolve());

  bool _resolve() => _platformOnline && !(_simulator?.isOffline ?? false);

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  void _emit(bool online) {
    _lastKnown = online;
    if (!_controller.isClosed) {
      _controller.add(online);
    }
  }

  @override
  Future<void> dispose() async {
    _simulator?.removeListener(_onSimulatorChanged);
    await _subscription?.cancel();
    await _controller.close();
  }
}
