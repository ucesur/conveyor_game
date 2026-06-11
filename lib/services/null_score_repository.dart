import 'score_repository.dart';

class NullScoreRepository implements ScoreRepository {
  const NullScoreRepository();

  @override
  Future<void> submitScore(ScoreEntry entry) async {}

  @override
  Future<List<ScoreEntry>> getTopScores({int limit = 10}) async => const [];
}
