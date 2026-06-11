import 'package:flutter/foundation.dart';
import 'score_repository.dart';
import 'null_score_repository.dart';

class ScoreService {
  ScoreService._();
  static final ScoreService instance = ScoreService._();

  ScoreRepository _repo = const NullScoreRepository();

  void configure(ScoreRepository repo) => _repo = repo;

  bool get isAvailable => _repo is! NullScoreRepository;

  Future<void> submitScore(ScoreEntry entry) async {
    try {
      await _repo.submitScore(entry);
      debugPrint('[ScoreService] Submitted score=${entry.score} level=${entry.level}');
    } catch (e) {
      debugPrint('[ScoreService] submitScore failed: $e');
    }
  }

  Future<List<ScoreEntry>> getTopScores({int limit = 10}) async {
    try {
      return await _repo.getTopScores(limit: limit);
    } catch (e) {
      debugPrint('[ScoreService] getTopScores failed: $e');
      return const [];
    }
  }
}
