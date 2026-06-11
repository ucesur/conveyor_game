import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/game_screen.dart';
import 'services/app_config.dart';
import 'services/score_service.dart';
import 'services/supabase_score_repository.dart';

const _supportedLocales = [
  Locale('en'),
  Locale('tr'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await _initScoreService();
  runApp(
    EasyLocalization(
      supportedLocales: _supportedLocales,
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const ConveyorMatchApp(),
    ),
  );
}

Future<void> _initScoreService() async {
  if (!AppConfig.isConfigured) {
    debugPrint('[ScoreService] Not configured — using null repo.');
    return;
  }
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseKey, // ignore: deprecated_member_use
    ).timeout(const Duration(seconds: 10));
    final repo = SupabaseScoreRepository(Supabase.instance.client);
    ScoreService.instance.configure(repo);
    debugPrint('[ScoreService] Ready.');
  } catch (e) {
    debugPrint('[ScoreService] Init error: $e');
  }
}

class ConveyorMatchApp extends StatelessWidget {
  const ConveyorMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conveyor Match',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}
