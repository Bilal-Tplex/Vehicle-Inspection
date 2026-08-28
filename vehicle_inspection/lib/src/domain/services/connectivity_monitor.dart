/// Reports whether the device currently has a usable connection.
///
/// Abstracted so the sync engine can be driven by a fake in tests, and so a
/// future implementation can upgrade from "an interface is up" to "our API
/// actually answered" without changing any caller.
abstract interface class ConnectivityMonitor {
  /// Current state, resolved on demand.
  Future<bool> isOnline();

  /// Emits on every transition. Implementations must emit the current value to
  /// new subscribers so a late listener is never left in the dark.
  Stream<bool> get onConnectivityChanged;

  /// Releases platform listeners.
  Future<void> dispose();
}
