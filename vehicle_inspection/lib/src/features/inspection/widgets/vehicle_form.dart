import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/validators.dart';
import '../../../domain/entities/vehicle.dart';

/// Vehicle capture form, shared by "New inspection" and "Edit vehicle".
///
/// Owning the controllers and validation in one widget means the two entry
/// points cannot drift apart — a rule added here applies to both.
class VehicleForm extends StatefulWidget {
  const VehicleForm({
    required this.onSubmit,
    required this.submitLabel,
    required this.submitIcon,
    this.initial,
    this.isBusy = false,
    this.header,
    super.key,
  });

  /// Pre-fills the fields when editing.
  final Vehicle? initial;

  /// Called with a validated vehicle. Errors are the caller's to report.
  final ValueChanged<Vehicle> onSubmit;

  final String submitLabel;
  final IconData submitIcon;
  final bool isBusy;
  final Widget? header;

  @override
  State<VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<VehicleForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _registration =
      TextEditingController(text: widget.initial?.registrationNumber ?? '');
  late final TextEditingController _make =
      TextEditingController(text: widget.initial?.make ?? '');
  late final TextEditingController _model =
      TextEditingController(text: widget.initial?.model ?? '');
  late final TextEditingController _year = TextEditingController(
    text: widget.initial?.manufacturingYear.toString() ?? '',
  );
  late final TextEditingController _vin =
      TextEditingController(text: widget.initial?.vin ?? '');
  late final TextEditingController _mileage = TextEditingController(
    text: widget.initial?.mileageKm.toString() ?? '',
  );

  @override
  void dispose() {
    _registration.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _vin.dispose();
    _mileage.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    widget.onSubmit(
      Vehicle(
        registrationNumber: _registration.text,
        make: _make.text,
        model: _model.text,
        manufacturingYear: int.parse(_year.text.trim()),
        vin: _vin.text,
        mileageKm: int.parse(_mileage.text.trim().replaceAll(',', '')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.isBusy;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 20),
          ],
          TextFormField(
            controller: _registration,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Registration number',
              hintText: 'ABC-123',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
            validator: Validators.registrationNumber,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _make,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Make'),
                  validator: (value) =>
                      Validators.required(value, field: 'Make'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _model,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Model'),
                  validator: (value) =>
                      Validators.required(value, field: 'Model'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _year,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    hintText: '2019',
                  ),
                  validator: Validators.manufacturingYear,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _mileage,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Mileage',
                    suffixText: 'km',
                  ),
                  validator: (value) => Validators.mileage(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _vin,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(17),
              // VIN uses a restricted alphabet; blocking bad characters as they
              // are typed beats a validation message after the fact.
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
            ],
            onFieldSubmitted: (_) => enabled ? _submit() : null,
            decoration: const InputDecoration(
              labelText: 'VIN / chassis number',
              hintText: '17 characters',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            validator: (value) => Validators.vin(value),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: enabled ? _submit : null,
            icon: widget.isBusy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Icon(widget.submitIcon),
            label: Text(widget.isBusy ? 'Saving...' : widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
