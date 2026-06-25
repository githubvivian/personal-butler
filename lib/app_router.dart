import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/providers/app_state.dart';
import 'features/auth/lock_screen.dart';
import 'features/birthday/birthday_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/family/child_detail_screen.dart';
import 'features/family/family_screen.dart';
import 'features/ideas/ideas_screen.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/inbox/ocr_confirm_screen.dart';
import 'features/inbox/voice_input_screen.dart';
import 'features/items/item_screens.dart';
import 'features/pending/pending_screen.dart';
import 'features/schedule/my_schedule_screen.dart';
import 'features/settings/backup_screen.dart';
import 'features/settings/schedule_settings_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/vault/vault_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter createRouter(AppState appState) {
  return GoRouter(
    navigatorKey: _rootKey,
    refreshListenable: appState,
    redirect: (context, state) {
      if (appState.loading) return null;
      final onLock = state.matchedLocation == '/lock';
      if (!appState.unlocked && !onLock) return '/lock';
      if (appState.unlocked && onLock) return '/inbox';
      return null;
    },
    initialLocation: '/inbox',
    routes: [
      GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/inbox', builder: (_, __) => const InboxScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pending',
                builder: (_, __) => const PendingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/family',
                builder: (_, __) => const FamilyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/me', builder: (_, __) => const SettingsScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/create',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CreateItemScreen(),
      ),
      GoRoute(
        path: '/item/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/voice',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const VoiceInputScreen(),
      ),
      GoRoute(
        path: '/ocr-confirm/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            OcrConfirmScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/schedule',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const MyScheduleScreen(),
      ),
      GoRoute(
        path: '/child/:owner',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            ChildDetailScreen(ownerId: state.pathParameters['owner']!),
      ),
      GoRoute(
        path: '/birthdays',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BirthdayScreen(),
      ),
      GoRoute(
        path: '/ideas',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const IdeasScreen(),
      ),
      GoRoute(
        path: '/vault',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const VaultScreen(),
      ),
      GoRoute(
        path: '/backup',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BackupScreen(),
      ),
      GoRoute(
        path: '/schedule-settings',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ScheduleSettingsScreen(),
      ),
    ],
  );
}
