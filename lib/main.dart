import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/game_screen.dart';
import 'services/app_config.dart';
import 'services/score_repository.dart';
import 'services/score_service.dart';
import 'services/supabase_score_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await _initScoreService();
  runApp(const ConveyorMatchApp());
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
    debugPrint('[ScoreService] Client created. Running diagnostics…');
    await _runDiagnostics(repo);
  } catch (e) {
    debugPrint('[ScoreService] Init error: $e');
  }
}

Future<void> _runDiagnostics(SupabaseScoreRepository repo) async {
  try {
    final rows = await repo.getTopScores(limit: 1);
    debugPrint('[ScoreService] SELECT ok — ${rows.length} row(s).');
  } catch (e) {
    debugPrint('[ScoreService] SELECT failed: $e');
  }
  try {
    await repo.submitScore(const ScoreEntry(score: 0, level: 0));
    debugPrint('[ScoreService] INSERT ok — test row written.');
  } catch (e) {
    debugPrint('[ScoreService] INSERT failed: $e');
  }
}

class ConveyorMatchApp extends StatelessWidget {
  const ConveyorMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conveyor Match',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}
