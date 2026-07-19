import 'lunar_date_helper.dart';

class BirthdayCountdown {
  const BirthdayCountdown({required this.date, required this.daysUntil});

  final DateTime date;
  final int daysUntil;
}

abstract final class BirthdayDateHelper {
  static bool isValidDate({
    required bool isLunar,
    required int month,
    required int day,
  }) {
    if (month < 1 || month > 12) return false;
    if (isLunar) return day >= 1 && day <= 30;
    if (day < 1 || day > 31) return false;

    final candidate = DateTime(2000, month, day);
    return candidate.month == month && candidate.day == day;
  }

  static BirthdayCountdown? nextCountdown({
    required bool isLunar,
    required int month,
    required int day,
    bool isLeapMonth = false,
    DateTime? from,
  }) {
    if (!isValidDate(isLunar: isLunar, month: month, day: day)) {
      return null;
    }

    final reference = from ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final occurrence = LunarDateHelper.nextSolarOccurrence(
      isLunar: isLunar,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      after: DateTime(today.year, today.month, today.day - 1),
    );
    if (occurrence == null) return null;

    return BirthdayCountdown(
      date: occurrence,
      daysUntil: DateTime.utc(
        occurrence.year,
        occurrence.month,
        occurrence.day,
      ).difference(DateTime.utc(today.year, today.month, today.day)).inDays,
    );
  }
}
