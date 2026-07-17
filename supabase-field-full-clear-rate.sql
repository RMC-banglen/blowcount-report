-- Per-worker override: pay 100% (instead of the default 50%) for "เคลียร์พื้นที่หน้างาน" work
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

ALTER TABLE field_workers ADD COLUMN IF NOT EXISTS full_clear_rate BOOLEAN DEFAULT false;
