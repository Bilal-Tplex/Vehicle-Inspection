import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/history/history_screen.dart';
import '../features/history/inspection_detail_screen.dart';
import '../features/inspection/checklist_screen.dart';
import '../features/inspection/edit_vehicle_screen.dart';
import '../features/inspection/new_inspection_screen.dart';
import '../features/inspection/submitted_screen.dart';
import '../features/inspection/summary_screen.dart';
import '../features/settings/settings_screen.dart';

/// Route names and the single place they are resolved.
///
/// The dashboard is deliberately absent: it is what the root gate shows when a
/// session exists, not something any screen pushes.
///
/// Named routes keep navigation declarative and make the arguments each screen
/// expects explicit in one file. Swapping this for `go_router` later means
/// rewriting this file and nothing else.
class AppRoutes {
  const AppRoutes._();

  static const String login = LoginScreen.routeName;
  static const String newInspection = NewInspectionScreen.routeName;
  static const String checklist = ChecklistScreen.routeName;
  static const String summary = SummaryScreen.routeName;
  static const String submitted = SubmittedScreen.routeName;
  static const String editVehicle = EditVehicleScreen.routeName;
  static const String history = HistoryScreen.routeName;
  static const String inspectionDetail = InspectionDetailScreen.routeName;
  static const String settings = SettingsScreen.routeName;

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case newInspection:
        return _build(settings, (_) => const NewInspectionScreen());

      case checklist:
        return _buildWithId(
          settings,
          (id) => ChecklistScreen(inspectionId: id),
        );

      case summary:
        return _buildWithId(settings, (id) => SummaryScreen(inspectionId: id));

      case submitted:
        return _buildWithId(
          settings,
          (id) => SubmittedScreen(inspectionId: id),
        );

      case editVehicle:
        return _buildWithId(
          settings,
          (id) => EditVehicleScreen(inspectionId: id),
        );

      case history:
        return _build(settings, (_) => const HistoryScreen());

      case inspectionDetail:
        return _buildWithId(
          settings,
          (id) => InspectionDetailScreen(inspectionId: id),
        );

      case AppRoutes.settings:
        return _build(settings, (_) => const SettingsScreen());

      default:
        return _build(settings, (_) => _UnknownRouteScreen(name: settings.name));
    }
  }

  static MaterialPageRoute<dynamic> _build(
    RouteSettings settings,
    WidgetBuilder builder,
  ) =>
      MaterialPageRoute<dynamic>(builder: builder, settings: settings);

  /// Routes that address a single inspection all take its id as the argument.
  ///
  /// A missing or wrongly-typed argument is a programming error, so it lands on
  /// an explicit screen rather than a null dereference deep inside a widget.
  static MaterialPageRoute<dynamic> _buildWithId(
    RouteSettings settings,
    Widget Function(String inspectionId) builder,
  ) {
    final argument = settings.arguments;
    if (argument is! String || argument.isEmpty) {
      return _build(
        settings,
        (_) => _UnknownRouteScreen(
          name: settings.name,
          detail: 'This route needs an inspection id.',
        ),
      );
    }
    return _build(settings, (_) => builder(argument));
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.name, this.detail});

  final String? name;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 48),
              const SizedBox(height: 14),
              Text(
                detail ?? 'No screen is registered for "$name".',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
