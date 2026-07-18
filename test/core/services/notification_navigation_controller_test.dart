import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/services/notification_navigation_controller.dart';

void main() {
  test('accepts only app-owned notification destinations', () {
    final controller = NotificationNavigationController.forTesting();

    controller.acceptPayload('/item/item-1');
    expect(controller.takePendingLocation(), '/item/item-1');

    controller.acceptPayload('/birthdays');
    expect(controller.takePendingLocation(), '/birthdays');

    controller.acceptPayload('/pending');
    expect(controller.takePendingLocation(), '/pending');

    for (final payload in <String?>[
      null,
      '',
      'https://example.invalid/item/item-1',
      '/unknown',
      '/item/',
      '/item/a/b',
      '../item/item-1',
    ]) {
      controller.acceptPayload(payload);
      expect(controller.takePendingLocation(), isNull, reason: payload);
    }

    controller.dispose();
  });

  test('replaces an older pending destination and can be consumed once', () {
    final controller = NotificationNavigationController.forTesting();

    controller.acceptPayload('/item/first');
    controller.acceptPayload('/item/second');

    expect(controller.pendingLocation, '/item/second');
    expect(controller.takePendingLocation(), '/item/second');
    expect(controller.takePendingLocation(), isNull);

    controller.dispose();
  });
}
