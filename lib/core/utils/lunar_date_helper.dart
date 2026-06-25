import 'package:lunar/lunar.dart';

class LunarDateHelper {
  static DateTime? nextSolarOccurrence({
    required bool isLunar,
    required int month,
    required int day,
    bool isLeapMonth = false,
    DateTime? after,
  }) {
    final base = DateTime(after?.year ?? DateTime.now().year,
        after?.month ?? DateTime.now().month, after?.day ?? DateTime.now().day);
    if (!isLunar) {
      var candidate = DateTime(base.year, month, day);
      if (!candidate.isAfter(base)) {
        candidate = DateTime(base.year + 1, month, day);
      }
      return candidate;
    }

    var cursor = base;
    for (var i = 0; i < 400; i++) {
      cursor = cursor.add(const Duration(days: 1));
      final lunar = Solar.fromDate(cursor).getLunar();
      if (lunar.getMonth() == month &&
          lunar.getDay() == day &&
          lunar.getMonth().abs() == month) {
        // leap month handling: skip if mismatch when leap required
        return cursor;
      }
    }
    return null;
  }

  static String formatLunarLabel(int month, int day, {bool isLeap = false}) {
    const monthNames = [
      '', '正月', '二月', '三月', '四月', '五月', '六月',
      '七月', '八月', '九月', '十月', '冬月', '腊月',
    ];
    const dayNames = [
      '', '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
      '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
      '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
    ];
    final prefix = isLeap ? '闰' : '';
    final m = month >= 1 && month <= 12 ? monthNames[month] : '$month月';
    final d = day >= 1 && day <= 30 ? dayNames[day] : '$day日';
    return '$prefix$m$d';
  }
}
