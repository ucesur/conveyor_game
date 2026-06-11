import 'package:supabase_flutter/supabase_flutter.dart';
import 'score_repository.dart';

class SupabaseScoreRepository implements ScoreRepository {
  final SupabaseClient _client;

  const SupabaseScoreRepository(this._client);

  @override
  Future<void> submitScore(ScoreEntry entry) async {
    await _client.from('high_scores').insert({
      'score': entry.score,
      'level': entry.level,
    });
  }

  @override
  Future<List<ScoreEntry>> getTopScores({int limit = 10}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('high_scores')
        .select('score, level, created_at')
        .order('score', ascending: false)
        .limit(limit);
    return rows
        .map((r) => ScoreEntry(
              score: r['score'] as int,
              level: r['level'] as int,
              createdAt: r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null,
            ))
        .toList();
  }
}
