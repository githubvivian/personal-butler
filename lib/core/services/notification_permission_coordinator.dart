import '../models/models.dart';
import 'notification_service.dart';

enum NotificationPermissionResult { notRequired, granted, denied, unavailable }

extension NotificationPermissionResultMessage on NotificationPermissionResult {
  String? get warningMessage {
    return switch (this) {
      NotificationPermissionResult.denied => '通知权限未开启，内容已保存',
      NotificationPermissionResult.unavailable => '通知权限暂不可用，内容已保存',
      NotificationPermissionResult.notRequired ||
      NotificationPermissionResult.granted => null,
    };
  }
}

bool itemHasActiveReminder(ItemModel item) {
  if (item.isDeleted ||
      item.inboxStatus != 'confirmed' ||
      item.status == 'done') {
    return false;
  }
  if (item.startAt != null) return true;
  return item.isPendingType &&
      item.status != 'done' &&
      item.nextFollowUpAt != null;
}

class NotificationPermissionCoordinator {
  NotificationPermissionCoordinator({
    required Future<bool?> Function() requestPermission,
  }) : this._(requestPermission);

  NotificationPermissionCoordinator._(this._requestPermission);

  static final NotificationPermissionCoordinator instance =
      NotificationPermissionCoordinator(
        requestPermission:
            NotificationService.instance.requestAndroidPermission,
      );

  final Future<bool?> Function() _requestPermission;
  Future<NotificationPermissionResult>? _inFlightRequest;

  Future<NotificationPermissionResult> requestThenPersist({
    required bool requiresPermission,
    required Future<void> Function() persist,
  }) async {
    final result = requiresPermission
        ? await _requestForActiveReminder()
        : NotificationPermissionResult.notRequired;
    await persist();
    return result;
  }

  Future<NotificationPermissionResult> _requestForActiveReminder() {
    final current = _inFlightRequest;
    if (current != null) return current;

    final request = _requestOnce();
    _inFlightRequest = request;
    request.then((_) {
      if (identical(_inFlightRequest, request)) {
        _inFlightRequest = null;
      }
    });
    return request;
  }

  Future<NotificationPermissionResult> _requestOnce() async {
    try {
      final result = await _requestPermission();
      if (result == null) return NotificationPermissionResult.unavailable;
      return result
          ? NotificationPermissionResult.granted
          : NotificationPermissionResult.denied;
    } catch (_) {
      return NotificationPermissionResult.unavailable;
    }
  }
}
