import 'package:intl/intl.dart';

/// Date and number formatting shared across screens.
class Formatters {
  const Formatters._();

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final NumberFormat _thousands = NumberFormat.decimalPattern();

  static String date(DateTime value) => _date.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);

  static String mileage(int km) => '${_thousands.format(km)} km';

  /// Short, human phrasing for list rows: "Today", "Yesterday", then the date.
  static String relativeDate(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final target = DateTime(value.year, value.month, value.day);
    final difference = today.difference(target).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference > 1 && difference < 7) return '$difference days ago';
    return _date.format(value);
  }
}
