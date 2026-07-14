-- Multi-leg distance + toll fee support for field_reports
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

ALTER TABLE field_reports ADD COLUMN IF NOT EXISTS distance_legs JSONB NOT NULL DEFAULT '[]';
ALTER TABLE field_reports ADD COLUMN IF NOT EXISTS toll_fee NUMERIC DEFAULT 0;
