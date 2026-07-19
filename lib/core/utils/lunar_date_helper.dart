import 'package:lunar/lunar.dart';

class LunarDateHelper {
  /// Product support horizon for finding the next birthday reminder.
  ///
  /// A `null` result can mean that no matching date exists within this window.
  static const int birthdayReminderHorizonYears = 150;

  static DateTime? nextSolarOccurrence({
    required bool isLunar,
    required int month,
    required int day,
    bool isLeapMonth = false,
    DateTime? after,
  }) {
    if (month < 1 || month > 12) {
      return null;
    }

    if (isLunar) {
      if (day < 1 || day > 30) {
        return null;
      }
    } else {
      if (day < 1 || day > 31) {
        return null;
      }
      final referenceDate = DateTime(2000, month, day);
      if (referenceDate.month != month || referenceDate.day != day) {
        return null;
      }
    }

    final now = after ?? DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    if (!isLunar) {
      for (var yearOffset = 0; yearOffset <= 8; yearOffset++) {
        try {
          final candidate = DateTime(base.year + yearOffset, month, day);
          if (candidate.month == month &&
              candidate.day == day &&
              candidate.isAfter(base)) {
            return candidate;
          }
        } on ArgumentError {
          return null;
        }
      }
      return null;
    }

    final targetMonth = isLeapMonth ? -month : month;
    final maxCandidateYear = base.year + birthdayReminderHorizonYears;
    for (
      var year = Solar.fromDate(base).getLunar().getYear();
      year <= maxCandidateYear;
      year++
    ) {
      final lunarMonth = LunarYear.fromYear(year).getMonth(targetMonth);
      if (lunarMonth != null && day <= lunarMonth.getDayCount()) {
        final solar = Lunar.fromYmd(year, targetMonth, day).getSolar();
        if (solar.getYear() > maxCandidateYear) {
          return null;
        }
        try {
          final candidate = DateTime(
            solar.getYear(),
            solar.getMonth(),
            solar.getDay(),
          );
          if (candidate.year <= maxCandidateYear && candidate.isAfter(base)) {
            return candidate;
          }
        } on ArgumentError {
          return null;
        }
      }
    }
    return null;
  }

  static String formatLunarLabel(int month, int day, {bool isLeap = false}) {
    const monthNames = [
      '',
      '正月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '冬月',
      '腊月',
    ];
    const dayNames = [
      '',
      '初一',
      '初二',
      '初三',
      '初四',
      '初五',
      '初六',
      '初七',
      '初八',
      '初九',
      '初十',
      '十一',
      '十二',
      '十三',
      '十四',
      '十五',
      '十六',
      '十七',
      '十八',
      '十九',
      '二十',
      '廿一',
      '廿二',
      '廿三',
      '廿四',
      '廿五',
      '廿六',
      '廿七',
      '廿八',
      '廿九',
      '三十',
    ];
    final prefix = isLeap ? '闰' : '';
    final m = month >= 1 && month <= 12 ? monthNames[month] : '$month月';
    final d = day >= 1 && day <= 30 ? dayNames[day] : '$day日';
    return '$prefix$m$d';
  }
}
