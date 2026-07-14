-- Monthly payroll lock for blowcount-report
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

CREATE TABLE IF NOT EXISTS field_month_locks (
  month TEXT PRIMARY KEY, -- 'YYYY-MM'
  locked_by TEXT,
  locked_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE field_month_locks DISABLE ROW LEVEL SECURITY;
