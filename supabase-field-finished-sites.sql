-- Marks a site as "job finished" so it can be hidden from ยอดสะสมรายเสา
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

CREATE TABLE IF NOT EXISTS field_finished_sites (
  site TEXT PRIMARY KEY,
  finished_at TIMESTAMPTZ DEFAULT NOW(),
  finished_by TEXT
);

ALTER TABLE field_finished_sites DISABLE ROW LEVEL SECURITY;
