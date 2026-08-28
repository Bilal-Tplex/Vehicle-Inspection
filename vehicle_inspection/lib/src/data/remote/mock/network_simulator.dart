import 'package:flutter/foundation.dart';

/// Conditions the mock backend pretends to operate under.
class NetworkConditions {
  const NetworkConditions({
    this.offline = false,
    this.failureRate = 0,
    this.latency = const Duration(milliseconds: 700),
  });

  /// Treat the device as having no connection, whatever the radio says.
  final bool offline;

  /// Probability in `[0, 1]` that a request returns a 500.
  final double failureRate;

  /// Artificial round-trip delay.
  final Duration latency;

  NetworkConditions copyWith({
    bool? offline,
    double? failureRate,
    Duration? latency,
  }) =>
      NetworkConditions(
        offline: offline ?? this.offline,
        failureRate: failureRate ?? this.failureRate,
        latency: latency ?? this.latency,
      );
}

/// Developer switches for exercising the offline and retry paths.
///
/// Reviewing offline behaviour should not require putting a phone into
/// airplane mode mid-inspection, so the Settings screen drives these directly.
/// Both the mock API and the connectivity monitor observe this object, which
/// keeps the simulated state consistent across the whole app.
///
/// In a production build this class and the mock API are simply not wired up.
class NetworkSimulator extends ValueNotifier<NetworkConditions> {
  NetworkSimulator([super.value = const NetworkConditions()]);

  bool get isOffline => value.offline;

  void setOffline(bool offline) => value = value.copyWith(offline: offline);

  void setFailureRate(double rate) =>
      value = value.copyWith(failureRate: rate.clamp(0, 1));

  void setLatency(Duration latency) => value = value.copyWith(latency: latency);
}
