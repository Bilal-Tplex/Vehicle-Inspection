import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/vehicle.dart';
import '../auth/auth_controller.dart';
import 'widgets/vehicle_form.dart';

/// Captures the vehicle, then creates the draft inspection.
///
/// The draft is written to SQLite before the checklist opens, so the evaluator
/// can be interrupted — or lose the app entirely — right after this screen and
/// still find their inspection waiting.
class NewInspectionScreen extends ConsumerStatefulWidget {
  const NewInspectionScreen({super.key});

  static const String routeName = '/inspection/new';

  @override
  ConsumerState<NewInspectionScreen> createState() =>
      _NewInspectionScreenState();
}

class _NewInspectionScreenState extends ConsumerState<NewInspectionScreen> {
  bool _isCreating = false;

  Future<void> _create(Vehicle vehicle) async {
    final evaluator = ref.read(currentEvaluatorProvider);
    if (evaluator == null) return;

    setState(() => _isCreating = true);
    try {
      final template =
          await ref.read(templateRepositoryProvider).getActiveTemplate();

      final inspection =
          await ref.read(inspectionRepositoryProvider).createDraft(
                evaluator: evaluator,
                template: template,
                vehicle: vehicle,
              );

      if (!mounted) return;
      // Replace rather than push: backing out of the checklist should land on
      // the dashboard, not on a form that would create a second draft.
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.checklist,
        arguments: inspection.id,
      );
    } catch (error) {
      if (!mounted) return;
      AppMessenger.showError(context, error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = ref.watch(activeTemplateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New Inspection')),
      body: VehicleForm(
        isBusy: _isCreating,
        submitLabel: 'Start checklist',
        submitIcon: Icons.checklist_rounded,
        onSubmit: _create,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle details',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              template.when(
                data: (value) =>
                    '${value.name} - ${value.totalPointCount} points',
                loading: () => 'Loading checklist...',
                error: (_, _) => 'Checklist unavailable',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
