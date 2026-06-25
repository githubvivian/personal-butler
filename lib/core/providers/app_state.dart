import 'package:flutter/foundation.dart';
import '../repositories/item_repository.dart';
import '../repositories/other_repositories.dart';
import '../repositories/schedule_repository.dart';
import '../security/session_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

class AppState extends ChangeNotifier {
  final items = ItemRepository();
  final schedules = ScheduleRepository();
  final birthdays = BirthdayRepository();
  final ideas = IdeaRepository();
  final vault = VaultRepository();
  final session = SessionService.instance;

  bool _unlocked = false;
  bool _initialized = false;
  bool _loading = true;

  bool get unlocked => _unlocked;
  bool get initialized => _initialized;
  bool get loading => _loading;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    await NotificationService.instance.init();
    _initialized = await session.isAppInitialized();
    if (_initialized) {
      _unlocked = await session.isSessionValid();
      if (_unlocked) {
        await ReminderSyncService.instance.syncAll(
          items: items,
          birthdays: birthdays,
        );
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> setupFirstRun() async {
    final ok = await session.authenticate(reason: '请验证指纹以初始化个人管家');
    if (!ok) return false;
    await session.markInitialized();
    _initialized = true;
    _unlocked = true;
    notifyListeners();
    return true;
  }

  Future<bool> unlock() async {
    final ok = await session.authenticate();
    if (ok) {
      await ReminderSyncService.instance.syncAll(
        items: items,
        birthdays: birthdays,
      );
    }
    _unlocked = ok;
    notifyListeners();
    return ok;
  }

  void lock() {
    session.lock();
    session.lockVault();
    _unlocked = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
