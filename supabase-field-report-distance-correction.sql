-- Distance-correction tracking for field_reports
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

ALTER TABLE field_reports ADD COLUMN IF NOT EXISTS original_distance_km NUMERIC;
ALTER TABLE field_reports ADD COLUMN IF NOT EXISTS original_distance_legs JSONB;
