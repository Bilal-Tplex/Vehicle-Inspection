import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/state_views.dart';
import '../../domain/entities/vehicle.dart';
import 'inspection_controller.dart';
import 'widgets/vehicle_form.dart';

/// Corrects vehicle details before submission.
///
/// Reached from the summary screen, which is where a mistyped VIN or mileage
/// tends to be noticed.
class EditVehicleScreen extends ConsumerStatefulWidget {
  const EditVehicleScreen({required this.inspectionId, super.key});

  static const String routeName = '/inspection/vehicle';

  final String inspectionId;

  @override
  ConsumerState<EditVehicleScreen> createState() => _EditVehicleScreenState();
}

class _EditVehicleScreenState extends ConsumerState<EditVehicleScreen> {
  bool _isSaving = false;

  Future<void> _save(Vehicle vehicle) async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(inspectionControllerProvider(widget.inspectionId).notifier)
          .updateVehicle(vehicle);
      if (!mounted) return;
      AppMessenger.showSuccess(context, 'Vehicle details updated');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      AppMessenger.showError(context, error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSession =
        ref.watch(inspectionControllerProvider(widget.inspectionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit vehicle')),
      body: asyncSession.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref
              .invalidate(inspectionControllerProvider(widget.inspectionId)),
        ),
        data: (session) => VehicleForm(
          initial: session.inspection.vehicle,
          isBusy: _isSaving,
          submitLabel: 'Save changes',
          submitIcon: Icons.save_outlined,
          onSubmit: _save,
        ),
      ),
    );
  }
}
