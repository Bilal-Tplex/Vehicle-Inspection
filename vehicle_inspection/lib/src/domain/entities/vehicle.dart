/// Vehicle identity captured at the start of an inspection.
class Vehicle {
  const Vehicle({
    required this.registrationNumber,
    required this.make,
    required this.model,
    required this.manufacturingYear,
    required this.vin,
    required this.mileageKm,
  });

  final String registrationNumber;
  final String make;
  final String model;
  final int manufacturingYear;

  /// VIN / chassis number, stored upper-cased.
  final String vin;
  final int mileageKm;

  String get displayName => '$make $model';

  String get displayNameWithYear => '$make $model ($manufacturingYear)';

  Vehicle copyWith({
    String? registrationNumber,
    String? make,
    String? model,
    int? manufacturingYear,
    String? vin,
    int? mileageKm,
  }) =>
      Vehicle(
        registrationNumber: registrationNumber ?? this.registrationNumber,
        make: make ?? this.make,
        model: model ?? this.model,
        manufacturingYear: manufacturingYear ?? this.manufacturingYear,
        vin: vin ?? this.vin,
        mileageKm: mileageKm ?? this.mileageKm,
      );

  Map<String, dynamic> toJson() => {
        'registrationNumber': registrationNumber,
        'make': make,
        'model': model,
        'manufacturingYear': manufacturingYear,
        'vin': vin,
        'mileageKm': mileageKm,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        registrationNumber: json['registrationNumber'] as String,
        make: json['make'] as String,
        model: json['model'] as String,
        manufacturingYear: (json['manufacturingYear'] as num).toInt(),
        vin: json['vin'] as String,
        mileageKm: (json['mileageKm'] as num).toInt(),
      );
}
