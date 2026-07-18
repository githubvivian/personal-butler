const _copyWithUnset = _CopyWithUnset();

final class _CopyWithUnset {
  const _CopyWithUnset();
}

T? _copyWithNullable<T>(Object? value, T? current) {
  return identical(value, _copyWithUnset) ? current : value as T?;
}

DateTime? _parseModelDate(dynamic value) {
  if (value == null) return null;
  return DateTime.parse(value as String);
}

const pendingItemTypes = <String>['task', 'reimbursement', 'review'];

bool isPendingItemType(String type) => pendingItemTypes.contains(type);

class ItemModel {
  final String id;
  final String type;
  final String title;
  final String? description;
  final String owner;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? location;
  final String? participants;
  final String status;
  final String inboxStatus;
  final String? pendingStatus;
  final DateTime? nextFollowUpAt;
  final double? amount;
  final String? ocrText;
  final String? notes;
  final int reminderMinutes;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ItemModel({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.owner = 'self',
    this.startAt,
    this.endAt,
    this.location,
    this.participants,
    this.status = 'active',
    this.inboxStatus = 'confirmed',
    this.pendingStatus,
    this.nextFollowUpAt,
    this.amount,
    this.ocrText,
    this.notes,
    this.reminderMinutes = 60,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPendingType => isPendingItemType(type);
  bool get isInbox => inboxStatus == 'inbox';
  bool get isSoftDeleted => isDeleted;

  ItemModel copyWith({
    String? type,
    String? title,
    Object? description = _copyWithUnset,
    String? owner,
    Object? startAt = _copyWithUnset,
    Object? endAt = _copyWithUnset,
    Object? location = _copyWithUnset,
    Object? participants = _copyWithUnset,
    String? status,
    String? inboxStatus,
    Object? pendingStatus = _copyWithUnset,
    Object? nextFollowUpAt = _copyWithUnset,
    Object? amount = _copyWithUnset,
    Object? ocrText = _copyWithUnset,
    Object? notes = _copyWithUnset,
    int? reminderMinutes,
    bool? isDeleted,
    DateTime? updatedAt,
  }) {
    return ItemModel(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: _copyWithNullable(description, this.description),
      owner: owner ?? this.owner,
      startAt: _copyWithNullable(startAt, this.startAt),
      endAt: _copyWithNullable(endAt, this.endAt),
      location: _copyWithNullable(location, this.location),
      participants: _copyWithNullable(participants, this.participants),
      status: status ?? this.status,
      inboxStatus: inboxStatus ?? this.inboxStatus,
      pendingStatus: _copyWithNullable(pendingStatus, this.pendingStatus),
      nextFollowUpAt: _copyWithNullable(nextFollowUpAt, this.nextFollowUpAt),
      amount: _copyWithNullable(amount, this.amount),
      ocrText: _copyWithNullable(ocrText, this.ocrText),
      notes: _copyWithNullable(notes, this.notes),
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      owner: map['owner'] as String? ?? 'self',
      startAt: _parseModelDate(map['start_at']),
      endAt: _parseModelDate(map['end_at']),
      location: map['location'] as String?,
      participants: map['participants'] as String?,
      status: map['status'] as String? ?? 'active',
      inboxStatus: map['inbox_status'] as String? ?? 'confirmed',
      pendingStatus: map['pending_status'] as String?,
      nextFollowUpAt: _parseModelDate(map['next_follow_up_at']),
      amount: map['amount'] != null ? (map['amount'] as num).toDouble() : null,
      ocrText: map['ocr_text'] as String?,
      notes: map['notes'] as String?,
      reminderMinutes: map['reminder_minutes'] as int? ?? 60,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'owner': owner,
      'start_at': startAt?.toIso8601String(),
      'end_at': endAt?.toIso8601String(),
      'location': location,
      'participants': participants,
      'status': status,
      'inbox_status': inboxStatus,
      'pending_status': pendingStatus,
      'next_follow_up_at': nextFollowUpAt?.toIso8601String(),
      'amount': amount,
      'ocr_text': ocrText,
      'notes': notes,
      'reminder_minutes': reminderMinutes,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class AttachmentModel {
  final String id;
  final String itemId;
  final String assetId;
  final String? displayName;
  final DateTime createdAt;

  const AttachmentModel({
    required this.id,
    required this.itemId,
    required this.assetId,
    this.displayName,
    required this.createdAt,
  });

  factory AttachmentModel.fromMap(Map<String, dynamic> map) {
    return AttachmentModel(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      assetId: map['asset_id'] as String,
      displayName: map['display_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'asset_id': assetId,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ScheduleSettingsModel {
  final String id;
  final int semesterStartWeek;
  final int semesterEndWeek;
  final DateTime? semesterStartDate;
  final DateTime updatedAt;

  const ScheduleSettingsModel({
    this.id = 'default',
    this.semesterStartWeek = 1,
    this.semesterEndWeek = 20,
    this.semesterStartDate,
    required this.updatedAt,
  });

  int get totalWeeks => (semesterEndWeek - semesterStartWeek) + 1;

  int? currentWeekFor(DateTime day) {
    final startDate = semesterStartDate;
    if (startDate == null) return null;
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final diffDays = normalizedDay.difference(normalizedStart).inDays;
    final computedWeek = semesterStartWeek + (diffDays ~/ 7);
    if (computedWeek < semesterStartWeek) return semesterStartWeek;
    if (computedWeek > semesterEndWeek) return semesterEndWeek;
    return computedWeek;
  }

  factory ScheduleSettingsModel.fromMap(Map<String, dynamic> map) {
    return ScheduleSettingsModel(
      id: map['id'] as String? ?? 'default',
      semesterStartWeek: map['semester_start_week'] as int? ?? 1,
      semesterEndWeek: map['semester_end_week'] as int? ?? 20,
      semesterStartDate: _parseModelDate(map['semester_start_date']),
      updatedAt: DateTime.parse(
        map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'semester_start_week': semesterStartWeek,
      'semester_end_week': semesterEndWeek,
      'semester_start_date': semesterStartDate?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ScheduleEntryModel {
  final String id;
  final String owner;
  final String title;
  final int weekday;
  final String startTime;
  final String endTime;
  final String? location;
  final int startWeek;
  final int endWeek;
  final String repeatMode;
  final String? weekPattern;
  final String? customWeeks;
  final bool isDeleted;
  final DateTime createdAt;

  const ScheduleEntryModel({
    required this.id,
    required this.owner,
    required this.title,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    this.location,
    this.startWeek = 1,
    this.endWeek = 20,
    this.repeatMode = 'all',
    this.weekPattern,
    this.customWeeks,
    this.isDeleted = false,
    required this.createdAt,
  });

  ScheduleEntryModel copyWith({
    String? owner,
    String? title,
    int? weekday,
    String? startTime,
    String? endTime,
    Object? location = _copyWithUnset,
    int? startWeek,
    int? endWeek,
    String? repeatMode,
    Object? weekPattern = _copyWithUnset,
    Object? customWeeks = _copyWithUnset,
    bool? isDeleted,
    DateTime? createdAt,
  }) {
    return ScheduleEntryModel(
      id: id,
      owner: owner ?? this.owner,
      title: title ?? this.title,
      weekday: weekday ?? this.weekday,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: _copyWithNullable(location, this.location),
      startWeek: startWeek ?? this.startWeek,
      endWeek: endWeek ?? this.endWeek,
      repeatMode: repeatMode ?? this.repeatMode,
      weekPattern: _copyWithNullable(weekPattern, this.weekPattern),
      customWeeks: _copyWithNullable(customWeeks, this.customWeeks),
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  List<int> get customWeekList {
    final raw = customWeeks;
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList()
      ..sort();
  }

  bool matchesWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    switch (repeatMode) {
      case 'odd':
        return week.isOdd;
      case 'even':
        return week.isEven;
      case 'custom':
        return customWeekList.contains(week);
      default:
        return true;
    }
  }

  String get weekDescription {
    final range = '$startWeek-$endWeek周';
    switch (repeatMode) {
      case 'odd':
        return '$range 单周';
      case 'even':
        return '$range 双周';
      case 'custom':
        final weeks = customWeekList.join('、');
        return weeks.isEmpty ? range : '第$weeks周';
      default:
        return range;
    }
  }

  int get startMinutes => _timeToMinutes(startTime);
  int get endMinutes => _timeToMinutes(endTime);

  List<int> activeWeeks() {
    final weeks = <int>[];
    for (int week = startWeek; week <= endWeek; week++) {
      if (matchesWeek(week)) weeks.add(week);
    }
    return weeks;
  }

  static int _timeToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }

  factory ScheduleEntryModel.fromMap(Map<String, dynamic> map) {
    return ScheduleEntryModel(
      id: map['id'] as String,
      owner: map['owner'] as String,
      title: map['title'] as String,
      weekday: map['weekday'] as int,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      location: map['location'] as String?,
      startWeek: map['start_week'] as int? ?? 1,
      endWeek: map['end_week'] as int? ?? 20,
      repeatMode: map['repeat_mode'] as String? ?? 'all',
      weekPattern: map['week_pattern'] as String?,
      customWeeks: map['custom_weeks'] as String?,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner': owner,
      'title': title,
      'weekday': weekday,
      'start_time': startTime,
      'end_time': endTime,
      'location': location,
      'start_week': startWeek,
      'end_week': endWeek,
      'repeat_mode': repeatMode,
      'week_pattern': weekPattern,
      'custom_weeks': customWeeks,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class BirthdayModel {
  final String id;
  final String name;
  final String relation;
  final bool isLunar;
  final int month;
  final int day;
  final bool isLeapMonth;
  final int remindDaysBefore;
  final bool isDeleted;
  final DateTime createdAt;

  const BirthdayModel({
    required this.id,
    required this.name,
    this.relation = '',
    required this.isLunar,
    required this.month,
    required this.day,
    this.isLeapMonth = false,
    this.remindDaysBefore = 3,
    this.isDeleted = false,
    required this.createdAt,
  });

  factory BirthdayModel.fromMap(Map<String, dynamic> map) {
    return BirthdayModel(
      id: map['id'] as String,
      name: map['name'] as String,
      relation: map['relation'] as String? ?? '',
      isLunar: (map['is_lunar'] as int? ?? 0) == 1,
      month: map['month'] as int,
      day: map['day'] as int,
      isLeapMonth: (map['is_leap_month'] as int? ?? 0) == 1,
      remindDaysBefore: map['remind_days_before'] as int? ?? 3,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'relation': relation,
      'is_lunar': isLunar ? 1 : 0,
      'month': month,
      'day': day,
      'is_leap_month': isLeapMonth ? 1 : 0,
      'remind_days_before': remindDaysBefore,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class IdeaModel {
  final String id;
  final String title;
  final String content;
  final String tag;
  final bool isStarred;
  final bool isDeleted;
  final DateTime createdAt;

  const IdeaModel({
    required this.id,
    required this.title,
    required this.content,
    this.tag = '生活',
    this.isStarred = false,
    this.isDeleted = false,
    required this.createdAt,
  });

  factory IdeaModel.fromMap(Map<String, dynamic> map) {
    return IdeaModel(
      id: map['id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      tag: map['tag'] as String? ?? '生活',
      isStarred: (map['is_starred'] as int? ?? 0) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'tag': tag,
      'is_starred': isStarred ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class VaultEntryModel {
  final String id;
  final String category;
  final String name;
  final String account;
  final String passwordEnc;
  final String? notesEnc;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VaultEntryModel({
    required this.id,
    required this.category,
    required this.name,
    required this.account,
    required this.passwordEnc,
    this.notesEnc,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VaultEntryModel.fromMap(Map<String, dynamic> map) {
    return VaultEntryModel(
      id: map['id'] as String,
      category: map['category'] as String,
      name: map['name'] as String,
      account: map['account'] as String,
      passwordEnc: map['password_enc'] as String,
      notesEnc: map['notes_enc'] as String?,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'account': account,
      'password_enc': passwordEnc,
      'notes_enc': notesEnc,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
