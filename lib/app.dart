import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app_router.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/app_state.dart';
import 'core/theme/app_theme.dart';

class PersonalButlerApp extends StatefulWidget {
  final AppState? appState;

  const PersonalButlerApp({super.key, this.appState});

  @override
  State<PersonalButlerApp> createState() => _PersonalButlerAppState();
}

class _PersonalButlerAppState extends State<PersonalButlerApp> {
  late final AppState _appState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
    _router = createRouter(_appState);
    _appState.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
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
        routerConfig: _router,
      ),
    );
  }
}
