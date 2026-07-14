import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/lunar_date_helper.dart';

void main() {
  test('birthday reminder horizon is 150 years', () {
    expect(LunarDateHelper.birthdayReminderHorizonYears, 150);
  });

  group('LunarDateHelper.nextSolarOccurrence', () {
    group('lunar dates', () {
      test('maps leap fourth month day 2 to 2020-05-24', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: true,
          month: 4,
          day: 2,
          isLeapMonth: true,
          after: DateTime(2020, 5, 23),
        );

        expect(occurrence, DateTime(2020, 5, 24));
      });

      test('finds the next matching leap month even when decades away', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: true,
          month: 4,
          day: 2,
          isLeapMonth: true,
          after: DateTime(2020, 5, 24),
        );

        expect(occurrence, DateTime(2058, 5, 23));
      });

      test('finds a month day 30 occurrence beyond 400 days', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: true,
          month: 4,
          day: 30,
          after: DateTime(2020, 5, 22),
        );

        expect(occurrence, DateTime(2023, 6, 17));
      });

      test('strictly excludes the after date for an ordinary lunar date', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: true,
          month: 1,
          day: 1,
          after: DateTime(2020, 1, 25),
        );

        expect(occurrence, DateTime(2021, 2, 12));
      });

      test('returns null when a matching leap date is beyond the horizon', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: true,
          month: 1,
          day: 30,
          isLeapMonth: true,
          after: DateTime(2026, 7, 15),
        );

        expect(occurrence, isNull);
      });
    });

    group('solar dates', () {
      test('supports a valid day 31 birthday', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: false,
          month: 1,
          day: 31,
          after: DateTime(2024, 1, 30),
        );

        expect(occurrence, DateTime(2024, 1, 31));
      });

      test('skips non-leap years for a February 29 birthday', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: false,
          month: 2,
          day: 29,
          after: DateTime(2024, 2, 29),
        );

        expect(occurrence, DateTime(2028, 2, 29));
      });

      test('finds February 29 across a non-leap century year', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: false,
          month: 2,
          day: 29,
          after: DateTime(2096, 2, 29),
        );

        expect(occurrence, DateTime(2104, 2, 29));
      });

      test('returns null when a candidate DateTime is out of range', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: false,
          month: 12,
          day: 31,
          after: DateTime(275760, 1, 1),
        );

        expect(occurrence, isNull);
      });

      test('strictly excludes the after date', () {
        final occurrence = LunarDateHelper.nextSolarOccurrence(
          isLunar: false,
          month: 7,
          day: 15,
          after: DateTime(2024, 7, 15),
        );

        expect(occurrence, DateTime(2025, 7, 15));
      });
    });

    group('validation', () {
      test('returns null for months outside 1 through 12', () {
        for (final month in [0, 13]) {
          expect(
            LunarDateHelper.nextSolarOccurrence(
              isLunar: false,
              month: month,
              day: 1,
              after: DateTime(2024, 1, 1),
            ),
            isNull,
          );
        }
      });

      test('returns null for lunar days outside 1 through 30', () {
        for (final day in [0, 31]) {
          expect(
            LunarDateHelper.nextSolarOccurrence(
              isLunar: true,
              month: 1,
              day: day,
              after: DateTime(2024, 1, 1),
            ),
            isNull,
          );
        }
      });

      test('returns null for solar days outside 1 through 31', () {
        for (final day in [0, 32, 100000001]) {
          expect(
            LunarDateHelper.nextSolarOccurrence(
              isLunar: false,
              month: 1,
              day: day,
              after: DateTime(2024, 1, 1),
            ),
            isNull,
          );
        }
      });

      test('returns null for impossible solar month and day combinations', () {
        expect(
          LunarDateHelper.nextSolarOccurrence(
            isLunar: false,
            month: 4,
            day: 31,
            after: DateTime(2024, 1, 1),
          ),
          isNull,
        );
        expect(
          LunarDateHelper.nextSolarOccurrence(
            isLunar: false,
            month: 2,
            day: 30,
            after: DateTime(2024, 1, 1),
          ),
          isNull,
        );
      });
    });
  });
}
