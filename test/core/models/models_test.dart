import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/models/models.dart';

void main() {
  group('ItemModel.copyWith nullable fields', () {
    test('retains every value when parameters are omitted', () {
      final original = _itemWithNullableValues();

      final copied = original.copyWith();

      expect(_itemNullableFields(copied), _itemNullableFields(original));
    });

    test('clears every value when null is explicit', () {
      final original = _itemWithNullableValues();

      final copied = original.copyWith(
        description: null,
        startAt: null,
        endAt: null,
        location: null,
        participants: null,
        pendingStatus: null,
        nextFollowUpAt: null,
        amount: null,
        ocrText: null,
        notes: null,
      );

      expect(_itemNullableFields(copied), {
        'description': null,
        'startAt': null,
        'endAt': null,
        'location': null,
        'participants': null,
        'pendingStatus': null,
        'nextFollowUpAt': null,
        'amount': null,
        'ocrText': null,
        'notes': null,
      });
    });

    test('replaces every value when non-null values are supplied', () {
      final original = _itemWithNullableValues();
      final replacementStart = DateTime.utc(2026, 8, 20, 10);
      final replacementEnd = DateTime.utc(2026, 8, 20, 11);
      final replacementFollowUp = DateTime.utc(2026, 8, 21, 9);

      final copied = original.copyWith(
        description: 'Replacement description',
        startAt: replacementStart,
        endAt: replacementEnd,
        location: 'Replacement location',
        participants: 'Replacement participants',
        pendingStatus: 'Replacement pending status',
        nextFollowUpAt: replacementFollowUp,
        amount: 99.5,
        ocrText: 'Replacement OCR text',
        notes: 'Replacement notes',
      );

      expect(_itemNullableFields(copied), {
        'description': 'Replacement description',
        'startAt': replacementStart,
        'endAt': replacementEnd,
        'location': 'Replacement location',
        'participants': 'Replacement participants',
        'pendingStatus': 'Replacement pending status',
        'nextFollowUpAt': replacementFollowUp,
        'amount': 99.5,
        'ocrText': 'Replacement OCR text',
        'notes': 'Replacement notes',
      });
    });
  });

  group('ScheduleEntryModel.copyWith nullable fields', () {
    test('retains every value when parameters are omitted', () {
      final original = _scheduleEntryWithNullableValues();

      final copied = original.copyWith();

      expect(
        _scheduleNullableFields(copied),
        _scheduleNullableFields(original),
      );
    });

    test('clears every value when null is explicit', () {
      final original = _scheduleEntryWithNullableValues();

      final copied = original.copyWith(
        location: null,
        weekPattern: null,
        customWeeks: null,
      );

      expect(_scheduleNullableFields(copied), {
        'location': null,
        'weekPattern': null,
        'customWeeks': null,
      });
    });

    test('replaces every value when non-null values are supplied', () {
      final original = _scheduleEntryWithNullableValues();

      final copied = original.copyWith(
        location: 'Replacement room',
        weekPattern: 'even',
        customWeeks: '2,4,6',
      );

      expect(_scheduleNullableFields(copied), {
        'location': 'Replacement room',
        'weekPattern': 'even',
        'customWeeks': '2,4,6',
      });
    });
  });
}

ItemModel _itemWithNullableValues() {
  final createdAt = DateTime.utc(2026, 7, 15, 8);
  return ItemModel(
    id: 'item-1',
    type: 'event',
    title: 'Original title',
    description: 'Original description',
    startAt: DateTime.utc(2026, 7, 15, 9),
    endAt: DateTime.utc(2026, 7, 15, 10),
    location: 'Original location',
    participants: 'Original participants',
    pendingStatus: 'Original pending status',
    nextFollowUpAt: DateTime.utc(2026, 7, 16, 9),
    amount: 42.5,
    ocrText: 'Original OCR text',
    notes: 'Original notes',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

Map<String, Object?> _itemNullableFields(ItemModel item) {
  return {
    'description': item.description,
    'startAt': item.startAt,
    'endAt': item.endAt,
    'location': item.location,
    'participants': item.participants,
    'pendingStatus': item.pendingStatus,
    'nextFollowUpAt': item.nextFollowUpAt,
    'amount': item.amount,
    'ocrText': item.ocrText,
    'notes': item.notes,
  };
}

ScheduleEntryModel _scheduleEntryWithNullableValues() {
  return ScheduleEntryModel(
    id: 'schedule-1',
    owner: 'self',
    title: 'Original class',
    weekday: 3,
    startTime: '09:00',
    endTime: '10:00',
    location: 'Original room',
    weekPattern: 'odd',
    customWeeks: '1,3,5',
    createdAt: DateTime.utc(2026, 7, 15, 8),
  );
}

Map<String, Object?> _scheduleNullableFields(ScheduleEntryModel entry) {
  return {
    'location': entry.location,
    'weekPattern': entry.weekPattern,
    'customWeeks': entry.customWeeks,
  };
}
