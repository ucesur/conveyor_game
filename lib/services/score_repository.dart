class ScoreEntry {
  final int score;
  final int level;
  final DateTime? createdAt;

  const ScoreEntry({required this.score, required this.level, this.createdAt});
}

abstract class ScoreRepository {
  Future<void> submitScore(ScoreEntry entry);
  Future<List<ScoreEntry>> getTopScores({int limit = 10});
}
