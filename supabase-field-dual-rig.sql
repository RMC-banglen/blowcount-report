-- Marks a day's report as "คุมปั่นจั่น 2 ตัว" (running 2 pile-driving rigs), which pays
-- double ค่าออกสนาม for that day, same as a Sunday/company holiday.
-- Run in Supabase SQL Editor (same project as supabase-field-report.sql)

ALTER TABLE field_reports ADD COLUMN IF NOT EXISTS dual_rig BOOLEAN DEFAULT false;
