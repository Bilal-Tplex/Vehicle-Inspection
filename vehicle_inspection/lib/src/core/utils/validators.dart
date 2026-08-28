/// Pure, UI-independent form validation rules.
///
/// Every function returns `null` when the value is acceptable and an error
/// message otherwise, matching the contract Flutter's [FormField] expects.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  // VIN excludes I, O and Q by ISO 3779.
  static final RegExp _vin = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _registration = RegExp(r'^[A-Z0-9][A-Z0-9 -]{2,14}$');

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_email.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value, {int minLength = 6}) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required.';
    if (text.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    return null;
  }

  static String? registrationNumber(String? value) {
    final trimmed = value?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty) return 'Registration number is required.';
    if (!_registration.hasMatch(trimmed)) {
      return 'Enter a valid registration number.';
    }
    return null;
  }

  /// VIN is optional on some markets, so an empty value passes. When present it
  /// must be a well-formed 17-character ISO 3779 number.
  static String? vin(String? value, {bool isRequired = true}) {
    final trimmed = value?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty) {
      return isRequired ? 'VIN / chassis number is required.' : null;
    }
    if (!_vin.hasMatch(trimmed)) {
      return 'VIN must be 17 characters and cannot contain I, O or Q.';
    }
    return null;
  }

  static String? manufacturingYear(String? value, {int? currentYear}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Manufacturing year is required.';
    final year = int.tryParse(trimmed);
    if (year == null) return 'Enter a valid year.';
    final maxYear = (currentYear ?? DateTime.now().year) + 1;
    if (year < 1900 || year > maxYear) {
      return 'Year must be between 1900 and $maxYear.';
    }
    return null;
  }

  static String? mileage(String? value, {int maxKm = 2000000}) {
    final trimmed = value?.trim().replaceAll(',', '') ?? '';
    if (trimmed.isEmpty) return 'Mileage is required.';
    final km = int.tryParse(trimmed);
    if (km == null) return 'Enter mileage as a whole number.';
    if (km < 0) return 'Mileage cannot be negative.';
    if (km > maxKm) return 'Mileage looks too high. Please check.';
    return null;
  }

  static String? maxLength(String? value, int limit, {String field = 'Value'}) {
    if (value != null && value.length > limit) {
      return '$field must be $limit characters or fewer.';
    }
    return null;
  }
}
