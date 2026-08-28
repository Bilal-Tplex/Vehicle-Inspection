import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/widgets/state_views.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Application root.
class VehicleInspectionApp extends ConsumerWidget {
  const VehicleInspectionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const _RootGate(),
    );
  }
}

/// Decides between the login screen and the dashboard.
///
/// Both the one-time startup work (seeding the checklist, starting the sync
/// engine) and the restored session are resolved here, so no screen below ever
/// has to cope with a half-initialised app.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);
    final session = ref.watch(authControllerProvider);

    // Startup touches only local storage, so this is a brief flash, not a
    // network wait — the app opens the same with or without a connection.
    if (startup.isLoading || session.isLoading) {
      return const Scaffold(
        body: LoadingView(message: 'Preparing your inspections...'),
      );
    }

    if (startup.hasError) {
      return Scaffold(
        body: ErrorView(
          error: startup.error!,
          onRetry: () => ref.invalidate(appStartupProvider),
        ),
      );
    }

    // A failed session restore means "signed out", never a dead end.
    final isSignedIn = session.value != null;
    return isSignedIn
        ? const DashboardScreen()
        : const LoginScreen();
  }
}
