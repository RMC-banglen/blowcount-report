-- Field report tables for banglen-report (worker daily report + car allowance)
-- Run in Supabase SQL Editor

CREATE TABLE IF NOT EXISTS field_workers (
  nick TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS field_reports (
  id BIGINT PRIMARY KEY,
  worker_nick TEXT NOT NULL,
  date DATE NOT NULL,
  site TEXT NOT NULL DEFAULT '',
  items JSONB NOT NULL DEFAULT '[]',
  time_in TEXT DEFAULT '',
  time_out TEXT DEFAULT '',
  vehicle TEXT DEFAULT 'company',
  distance_km NUMERIC DEFAULT 0,
  work_type TEXT DEFAULT 'pile',
  note TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS field_homes (
  worker_nick TEXT PRIMARY KEY,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS field_settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT INTO field_settings (key, value) VALUES ('rate_car', '250') ON CONFLICT (key) DO NOTHING;
INSERT INTO field_settings (key, value) VALUES ('rate_moto', '100') ON CONFLICT (key) DO NOTHING;
-- admin_password_hash is left unset on purpose: the app prompts to set it
-- on first visit to the admin page and stores a SHA-256 hash, never the
-- plain password.

INSERT INTO field_workers (nick, full_name) VALUES
  ('วัฒน์', 'นายธานุวัฒน์ มุทาพร'),
  ('หมาย', 'นายสมหมาย สีสวย'),
  ('ตั้ม', 'นายณรงฤทธิ์ วิชิต'),
  ('ชัย', 'นายพรชัย ตะเพียนทอง'),
  ('กันต์', 'นายกันตพงศ์ พานิชพงษ์'),
  ('อุ้ย', 'นายโชคชัย ยอดเทียน'),
  ('เกมส์', 'นายศักดิ์ดา มิ่งละกูล'),
  ('อาร์ม', 'นายนิติพล ชังคะนาค'),
  ('ไลลา', 'น.ส.เกล็ดดาว จีนขวั้น'),
  ('จิ้ม', 'นายนิธิวัชน์ ประหยัดทรัพย์'),
  ('แทน', 'น.ส.กนกนุช สวยรูป'),
  ('เจมม์', 'นายจีระพล เจริญสุข'),
  ('นัท', 'นายนฤมิตร จันทร์พิมพ์'),
  ('เจ๊ก', 'นายอิทธิกร ทิพย์สิงห์'),
  ('ชานนท์', 'นายชานนท์ สาริกา')
ON CONFLICT (nick) DO NOTHING;

ALTER TABLE field_workers DISABLE ROW LEVEL SECURITY;
ALTER TABLE field_reports DISABLE ROW LEVEL SECURITY;
ALTER TABLE field_homes DISABLE ROW LEVEL SECURITY;
ALTER TABLE field_settings DISABLE ROW LEVEL SECURITY;
