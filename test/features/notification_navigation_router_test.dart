import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/app_router.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/services/notification_navigation_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('keeps a notification destination until the session unlocks', (
    tester,
  ) async {
    final appState = _RouterAppState();
    final navigation = NotificationNavigationController.forTesting()
      ..acceptPayload('/item/tapped-item');
    final router = createRouter(appState, notificationNavigation: navigation);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/lock');
    expect(navigation.pendingLocation, '/item/tapped-item');

    appState.setUnlocked(true);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/item/tapped-item');
    expect(navigation.pendingLocation, isNull);
    expect(find.text('事项不存在或已删除'), findsOneWidget);
    expect(tester.takeException(), isNull);

    router.dispose();
    navigation.dispose();
    appState.dispose();
  });
}

class _RouterAppState extends AppState {
  _RouterAppState()
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => true,
        validateSession: () async => false,
        syncReminders: () async {},
      );

  final ItemRepository _items = _MissingItemRepository();
  bool _isUnlocked = false;

  @override
  bool get loading => false;

  @override
  bool get initialized => true;

  @override
  bool get unlocked => _isUnlocked;

  @override
  Object? get bootstrapError => null;

  @override
  ItemRepository get items => _items;

  @override
  Future<bool> unlock() async => false;

  void setUnlocked(bool value) {
    _isUnlocked = value;
    notifyListeners();
  }
}

class _MissingItemRepository extends ItemRepository {
  @override
  Future<ItemModel?> getById(String id) async => null;
}
