-- Worker leave/absence tracking for blowcount-report
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

CREATE TABLE IF NOT EXISTS field_leaves (
  id BIGINT PRIMARY KEY,
  worker_nick TEXT NOT NULL,
  date DATE NOT NULL,
  leave_type TEXT NOT NULL, -- 'sunday' | 'holiday' | 'sick' | 'vacation' | 'personal'
  reason TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE field_leaves DISABLE ROW LEVEL SECURITY;
