import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_inspection/src/core/utils/validators.dart';

void main() {
  group('email', () {
    test('accepts ordinary addresses', () {
      expect(Validators.email('evaluator@test.com'), isNull);
      expect(Validators.email('first.last+tag@sub.example.co'), isNull);
    });

    test('rejects empty and malformed values', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('evaluator'), isNotNull);
      expect(Validators.email('evaluator@'), isNotNull);
      expect(Validators.email('evaluator@test'), isNotNull);
    });
  });

  group('password', () {
    test('enforces the minimum length', () {
      expect(Validators.password('password123'), isNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password(''), isNotNull);
    });
  });

  group('VIN', () {
    test('accepts a well-formed 17-character number', () {
      expect(Validators.vin('JTDBR32E720123456'), isNull);
    });

    test('is case insensitive', () {
      expect(Validators.vin('jtdbr32e720123456'), isNull);
    });

    test('rejects the wrong length', () {
      expect(Validators.vin('JTDBR32E7201234'), isNotNull);
      expect(Validators.vin('JTDBR32E7201234567'), isNotNull);
    });

    test('rejects I, O and Q, which ISO 3779 excludes', () {
      expect(Validators.vin('JTDBR32E72012345I'), isNotNull);
      expect(Validators.vin('JTDBR32E72012345O'), isNotNull);
      expect(Validators.vin('JTDBR32E72012345Q'), isNotNull);
    });

    test('can be optional for markets that do not record it', () {
      expect(Validators.vin('', isRequired: false), isNull);
      expect(Validators.vin('', isRequired: true), isNotNull);
      // An optional field that is filled in is still validated.
      expect(Validators.vin('TOO-SHORT', isRequired: false), isNotNull);
    });
  });

  group('manufacturing year', () {
    test('accepts a plausible year', () {
      expect(Validators.manufacturingYear('2019', currentYear: 2026), isNull);
    });

    test('allows next year for a brand new vehicle', () {
      expect(Validators.manufacturingYear('2027', currentYear: 2026), isNull);
    });

    test('rejects the future and the distant past', () {
      expect(
        Validators.manufacturingYear('2028', currentYear: 2026),
        isNotNull,
      );
      expect(Validators.manufacturingYear('1899'), isNotNull);
    });

    test('rejects non-numeric input', () {
      expect(Validators.manufacturingYear('twenty'), isNotNull);
      expect(Validators.manufacturingYear(''), isNotNull);
    });
  });

  group('mileage', () {
    test('accepts whole numbers with or without separators', () {
      expect(Validators.mileage('84500'), isNull);
      expect(Validators.mileage('84,500'), isNull);
      expect(Validators.mileage('0'), isNull);
    });

    test('rejects implausible and malformed values', () {
      expect(Validators.mileage(''), isNotNull);
      expect(Validators.mileage('lots'), isNotNull);
      expect(Validators.mileage('-5'), isNotNull);
      expect(Validators.mileage('9999999999'), isNotNull);
    });
  });

  group('registration number', () {
    test('accepts common formats', () {
      expect(Validators.registrationNumber('ABC-123'), isNull);
      expect(Validators.registrationNumber('LEA 4021'), isNull);
      expect(Validators.registrationNumber('abc123'), isNull);
    });

    test('rejects empty and too-short values', () {
      expect(Validators.registrationNumber(''), isNotNull);
      expect(Validators.registrationNumber('A'), isNotNull);
    });
  });

  group('required', () {
    test('treats whitespace as empty', () {
      expect(Validators.required('   '), isNotNull);
      expect(Validators.required('Toyota'), isNull);
    });

    test('names the field in the message', () {
      expect(Validators.required('', field: 'Make'), contains('Make'));
    });
  });
}
