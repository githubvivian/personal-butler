import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/birthday_date_helper.dart';

void main() {
  group('BirthdayDateHelper validation', () {
    test('accepts a recurring solar leap day', () {
      expect(
        BirthdayDateHelper.isValidDate(isLunar: false, month: 2, day: 29),
        isTrue,
      );
    });

    test('rejects impossible and out-of-range solar dates', () {
      for (final date in [(month: 2, day: 30), (month: 13, day: 32)]) {
        expect(
          BirthdayDateHelper.isValidDate(
            isLunar: false,
            month: date.month,
            day: date.day,
          ),
          isFalse,
        );
      }
    });

    test('accepts only lunar months 1 through 12 and days 1 through 30', () {
      for (final date in [(month: 1, day: 1), (month: 12, day: 30)]) {
        expect(
          BirthdayDateHelper.isValidDate(
            isLunar: true,
            month: date.month,
            day: date.day,
          ),
          isTrue,
        );
      }
      for (final date in [
        (month: 0, day: 1),
        (month: 13, day: 1),
        (month: 1, day: 0),
        (month: 1, day: 31),
      ]) {
        expect(
          BirthdayDateHelper.isValidDate(
            isLunar: true,
            month: date.month,
            day: date.day,
          ),
          isFalse,
        );
      }
    });
  });

  group('BirthdayDateHelper.nextCountdown', () {
    test('includes a birthday later on the same local calendar day', () {
      final countdown = BirthdayDateHelper.nextCountdown(
        isLunar: false,
        month: 7,
        day: 16,
        from: DateTime(2026, 7, 16, 23, 59),
      );

      expect(countdown?.date, DateTime(2026, 7, 16));
      expect(countdown?.daysUntil, 0);
    });

    test('counts tomorrow as one local calendar day', () {
      final countdown = BirthdayDateHelper.nextCountdown(
        isLunar: false,
        month: 7,
        day: 17,
        from: DateTime(2026, 7, 16, 23, 59),
      );

      expect(countdown?.date, DateTime(2026, 7, 17));
      expect(countdown?.daysUntil, 1);
    });

    test('includes an ordinary lunar birthday on the same day', () {
      final countdown = BirthdayDateHelper.nextCountdown(
        isLunar: true,
        month: 1,
        day: 1,
        from: DateTime(2020, 1, 25, 23, 59),
      );

      expect(countdown?.date, DateTime(2020, 1, 25));
      expect(countdown?.daysUntil, 0);
    });

    test('passes the leap-month flag through to lunar conversion', () {
      final countdown = BirthdayDateHelper.nextCountdown(
        isLunar: true,
        month: 4,
        day: 2,
        isLeapMonth: true,
        from: DateTime(2020, 5, 23, 23, 59),
      );

      expect(countdown?.date, DateTime(2020, 5, 24));
      expect(countdown?.daysUntil, 1);
    });
  });
}
