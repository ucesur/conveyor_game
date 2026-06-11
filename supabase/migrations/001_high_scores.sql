-- Run this in the Supabase SQL editor for project conveyor_game

CREATE TABLE IF NOT EXISTS high_scores (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  score     integer     NOT NULL,
  level     integer     NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast leaderboard queries
CREATE INDEX IF NOT EXISTS high_scores_score_desc ON high_scores (score DESC);

-- Explicit grants so the anon role can read and insert
GRANT SELECT, INSERT ON high_scores TO anon;
GRANT SELECT, INSERT ON high_scores TO authenticated;

-- Row-level security: anyone can read and insert, nobody can update/delete
ALTER TABLE high_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public read"   ON high_scores;
DROP POLICY IF EXISTS "public insert" ON high_scores;

CREATE POLICY "public read"   ON high_scores FOR SELECT USING (true);
CREATE POLICY "public insert" ON high_scores FOR INSERT WITH CHECK (true);
