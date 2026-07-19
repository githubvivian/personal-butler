import 'package:flutter/foundation.dart';

/// Holds a safe, deferred destination from a notification tap.
///
/// Notifications can be tapped while the app is locked or before the router
/// has finished bootstrapping. Keeping the destination here avoids losing the
/// intent while still letting the normal authentication redirect run first.
class NotificationNavigationController extends ChangeNotifier {
  NotificationNavigationController._();

  @visibleForTesting
  NotificationNavigationController.forTesting();

  static final NotificationNavigationController instance =
      NotificationNavigationController._();

  String? _pendingLocation;
  bool _disposed = false;

  String? get pendingLocation => _pendingLocation;

  /// Accepts only destinations produced by this app's notification scheduler.
  /// Unknown or malformed payloads are ignored instead of being treated as a
  /// deep link supplied by an external caller.
  void acceptPayload(String? payload) {
    final location = locationFromPayload(payload);
    if (location == null) return;
    _pendingLocation = location;
    if (!_disposed) notifyListeners();
  }

  /// Takes a pending destination once the caller has confirmed the app is
  /// unlocked and ready to navigate.
  String? takePendingLocation() {
    final location = _pendingLocation;
    _pendingLocation = null;
    return location;
  }

  /// Clears the destination only after the router confirms it reached the
  /// same location. This prevents a redirect error from silently losing the
  /// user's notification tap.
  void markLocationReached(String location) {
    if (_pendingLocation == location) _pendingLocation = null;
  }

  @visibleForTesting
  void clear() => _pendingLocation = null;

  static String? locationFromPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final path = uri.path;
    if (path == '/pending' || path == '/birthdays') return path;
    if (!path.startsWith('/item/')) return null;
    final id = path.substring('/item/'.length);
    if (id.isEmpty || id.contains('/')) return null;
    return '/item/$id';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
