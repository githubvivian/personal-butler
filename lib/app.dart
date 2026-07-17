import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app_router.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/startup_screen.dart';

class PersonalButlerApp extends StatefulWidget {
  final AppState? appState;

  const PersonalButlerApp({super.key, this.appState});

  @override
  State<PersonalButlerApp> createState() => _PersonalButlerAppState();
}

class _PersonalButlerAppState extends State<PersonalButlerApp>
    with WidgetsBindingObserver {
  AppState? _appState;
  GoRouter? _router;
  bool _ownsAppState = false;
  int _replacementGeneration = 0;
  Future<void> _replacementTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _replaceAppState(widget.appState ?? AppState(), widget.appState == null);
  }

  @override
  void didUpdateWidget(covariant PersonalButlerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.appState, widget.appState)) return;
    _replaceAppState(widget.appState ?? AppState(), widget.appState == null);
  }

  void _replaceAppState(AppState nextAppState, bool ownsNextAppState) {
    final replacementGeneration = ++_replacementGeneration;
    final previousAppState = _appState;
    final previousRouter = _router;
    final ownsPreviousAppState = _ownsAppState;
    final queuedReplacement = _replacementTail;

    _appState = null;
    _router = null;
    _ownsAppState = false;
    previousRouter?.dispose();

    final previousDeactivation =
        previousAppState?.deactivateSessionLifecycle() ?? Future<void>.value();
    final nextDeactivation = identical(previousAppState, nextAppState)
        ? previousDeactivation
        : nextAppState.deactivateSessionLifecycle();

    _replacementTail = _completeReplacement(
      queuedReplacement: queuedReplacement,
      previousAppState: previousAppState,
      previousDeactivation: previousDeactivation,
      ownsPreviousAppState: ownsPreviousAppState,
      nextAppState: nextAppState,
      nextDeactivation: nextDeactivation,
      ownsNextAppState: ownsNextAppState,
      replacementGeneration: replacementGeneration,
    );
  }

  Future<void> _completeReplacement({
    required Future<void> queuedReplacement,
    required AppState? previousAppState,
    required Future<void> previousDeactivation,
    required bool ownsPreviousAppState,
    required AppState nextAppState,
    required Future<void> nextDeactivation,
    required bool ownsNextAppState,
    required int replacementGeneration,
  }) async {
    await queuedReplacement;
    await previousDeactivation;
    if (ownsPreviousAppState) {
      previousAppState?.dispose();
    }
    await nextDeactivation;

    if (!mounted || replacementGeneration != _replacementGeneration) {
      if (ownsNextAppState) nextAppState.dispose();
      return;
    }

    await nextAppState.activateSessionLifecycle();
    if (!mounted || replacementGeneration != _replacementGeneration) {
      await nextAppState.deactivateSessionLifecycle();
      if (ownsNextAppState) nextAppState.dispose();
      return;
    }

    nextAppState.bootstrap();
    final nextRouter = createRouter(nextAppState);
    setState(() {
      _appState = nextAppState;
      _router = nextRouter;
      _ownsAppState = ownsNextAppState;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appState = _appState;
    if (state == AppLifecycleState.resumed && appState != null) {
      unawaited(appState.revalidateSession());
    }
  }

  @override
  void dispose() {
    _replacementGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    _router?.dispose();
    final appState = _appState;
    if (appState != null) {
      final deactivation = appState.deactivateSessionLifecycle();
      if (_ownsAppState) {
        unawaited(deactivation.whenComplete(appState.dispose));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = _appState;
    final router = _router;
    if (appState == null || router == null) {
      return MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const StartupLoadingScreen(),
      );
    }

    return ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    );
  }
}
