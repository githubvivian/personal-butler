DateTime clampDateToPickerBounds(
  DateTime value, {
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final normalizedValue = DateTime(value.year, value.month, value.day);
  final normalizedFirst = DateTime(
    firstDate.year,
    firstDate.month,
    firstDate.day,
  );
  final normalizedLast = DateTime(lastDate.year, lastDate.month, lastDate.day);
  assert(!normalizedLast.isBefore(normalizedFirst));
  if (normalizedValue.isBefore(normalizedFirst)) return normalizedFirst;
  if (normalizedValue.isAfter(normalizedLast)) return normalizedLast;
  return normalizedValue;
}
