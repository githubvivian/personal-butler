import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/date_picker_bounds.dart';

void main() {
  test('clamps by calendar fields instead of absolute UTC instant', () {
    final result = clampDateToPickerBounds(
      DateTime.utc(2019, 12, 31, 23),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    expect(result, DateTime(2020));
    expect(result.isUtc, isFalse);
  });

  test('returns an in-range value normalized to its calendar date', () {
    final result = clampDateToPickerBounds(
      DateTime.utc(2026, 7, 19, 23, 59),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    expect(result, DateTime(2026, 7, 19));
  });
}
