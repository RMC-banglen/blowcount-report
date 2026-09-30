-- Lock down the database so only the app's intended actions work, even for someone calling the
-- Supabase API directly with the public key from the page:
--   * admin PINs move out of the readable field_settings.admin_users into a hidden table and are
--     checked here (admin_login) — the page gets a 12-hour session token, sent as x-admin-token
--   * 5 wrong PINs for a name locks that name for 15 minutes
--   * everyone can read; workers (no token) can only add/edit/delete reports and leaves in months
--     that aren't locked; everything else needs an admin token; admin users only via the owner
-- Run once in Supabase SQL Editor (same project as supabase-field-report.sql). Safe to re-run.
-- Everyone will need to log in to the admin page again afterwards.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------- hidden admin tables
CREATE TABLE IF NOT EXISTS field_admin_secrets (
  name TEXT PRIMARY KEY,
  pin_hash TEXT NOT NULL          -- SHA-256 of the PIN, as the page has always computed it
);
CREATE TABLE IF NOT EXISTS field_admin_sessions (
  token UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_name TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '12 hours'
);
CREATE TABLE IF NOT EXISTS field_admin_login_fails (
  name TEXT PRIMARY KEY,
  fails INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ
);
-- RLS on with no policies = the public key can't touch them at all
ALTER TABLE field_admin_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_admin_login_fails ENABLE ROW LEVEL SECURITY;

-- move existing PIN hashes out of the public admin list (idempotent)
INSERT INTO field_admin_secrets (name, pin_hash)
SELECT a->>'name', a->>'hash'
FROM field_settings s, json_array_elements(s.value::json) a
WHERE s.key = 'admin_users' AND a->>'hash' IS NOT NULL
ON CONFLICT (name) DO UPDATE SET pin_hash = EXCLUDED.pin_hash;

UPDATE field_settings
SET value = (SELECT COALESCE(json_agg(a::jsonb - 'hash'), '[]'::json)::text FROM json_array_elements(value::json) a)
WHERE key = 'admin_users';

-- ---------------------------------------------------------------- who is calling
-- the admin behind the x-admin-token header, or NULL
CREATE OR REPLACE FUNCTION field_admin_name() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT admin_name FROM field_admin_sessions
  WHERE token::text = NULLIF(current_setting('request.headers', true)::json->>'x-admin-token', '')
    AND expires_at > NOW()
$$;

CREATE OR REPLACE FUNCTION field_is_owner() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM field_settings s, json_array_elements(s.value::json) a
    WHERE s.key = 'admin_users' AND a->>'name' = field_admin_name() AND a->>'role' = 'owner'
  )
$$;

CREATE OR REPLACE FUNCTION field_month_locked(d DATE) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM field_month_locks WHERE month = to_char(d, 'YYYY-MM'))
$$;

-- ---------------------------------------------------------------- login / logout
-- returns a session token, NULL for a wrong PIN; raises 'locked' while locked out
CREATE OR REPLACE FUNCTION admin_login(p_name TEXT, p_hash TEXT) RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE f field_admin_login_fails; t UUID;
BEGIN
  SELECT * INTO f FROM field_admin_login_fails WHERE name = p_name;
  IF f.locked_until IS NOT NULL AND f.locked_until > NOW() THEN
    RAISE EXCEPTION 'locked';
  END IF;
  IF f.locked_until IS NOT NULL THEN  -- lock has expired: start counting again
    DELETE FROM field_admin_login_fails WHERE name = p_name;
  END IF;
  IF EXISTS (SELECT 1 FROM field_admin_secrets WHERE name = p_name AND pin_hash = p_hash) THEN
    DELETE FROM field_admin_login_fails WHERE name = p_name;
    DELETE FROM field_admin_sessions WHERE expires_at < NOW();
    INSERT INTO field_admin_sessions (admin_name) VALUES (p_name) RETURNING token INTO t;
    RETURN t::text;
  END IF;
  INSERT INTO field_admin_login_fails (name, fails) VALUES (p_name, 1)
  ON CONFLICT (name) DO UPDATE SET
    fails = field_admin_login_fails.fails + 1,
    locked_until = CASE WHEN field_admin_login_fails.fails + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' END;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION admin_logout() RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM field_admin_sessions
  WHERE token::text = NULLIF(current_setting('request.headers', true)::json->>'x-admin-token', '')
$$;

-- the logged-in admin's name, or NULL if the token is missing/expired
CREATE OR REPLACE FUNCTION admin_whoami() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT field_admin_name()
$$;

-- ---------------------------------------------------------------- managing admin users
-- owner only (or anyone while no admin exists yet, for first-time setup). p_users is the full list
-- without PINs, p_pins {name: hash} sets new PINs, p_renames {old: new} carries a PIN across a rename
CREATE OR REPLACE FUNCTION admin_save_users(p_users JSON, p_pins JSON DEFAULT '{}', p_renames JSON DEFAULT '{}') RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE k TEXT; v TEXT;
BEGIN
  IF NOT (field_is_owner() OR NOT EXISTS (SELECT 1 FROM field_admin_secrets)) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  FOR k, v IN SELECT * FROM json_each_text(COALESCE(p_renames, '{}')) LOOP
    UPDATE field_admin_secrets SET name = v WHERE name = k;
    UPDATE field_admin_sessions SET admin_name = v WHERE admin_name = k;
  END LOOP;
  FOR k, v IN SELECT * FROM json_each_text(COALESCE(p_pins, '{}')) LOOP
    INSERT INTO field_admin_secrets (name, pin_hash) VALUES (k, v)
    ON CONFLICT (name) DO UPDATE SET pin_hash = EXCLUDED.pin_hash;
  END LOOP;
  INSERT INTO field_settings (key, value)
  VALUES ('admin_users', (SELECT COALESCE(json_agg(a::jsonb - 'hash'), '[]'::json)::text FROM json_array_elements(p_users) a))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  DELETE FROM field_admin_secrets WHERE name NOT IN (SELECT a->>'name' FROM json_array_elements(p_users) a);
  DELETE FROM field_admin_sessions WHERE admin_name NOT IN (SELECT a->>'name' FROM json_array_elements(p_users) a);
END $$;

-- a non-owner admin editing themselves: only their own name, position and PIN
CREATE OR REPLACE FUNCTION admin_update_self(p_new_name TEXT, p_position TEXT, p_hash TEXT DEFAULT NULL) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me TEXT := field_admin_name();
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_new_name <> me AND EXISTS (
    SELECT 1 FROM field_settings s, json_array_elements(s.value::json) a WHERE s.key = 'admin_users' AND a->>'name' = p_new_name
  ) THEN RAISE EXCEPTION 'name taken'; END IF;
  UPDATE field_settings SET value = (
    SELECT json_agg(CASE WHEN a->>'name' = me
      THEN a::jsonb || jsonb_build_object('name', p_new_name, 'position', COALESCE(p_position, ''))
      ELSE a::jsonb END)::text
    FROM json_array_elements(value::json) a
  ) WHERE key = 'admin_users';
  UPDATE field_admin_secrets SET name = p_new_name, pin_hash = COALESCE(p_hash, pin_hash) WHERE name = me;
  UPDATE field_admin_sessions SET admin_name = p_new_name WHERE admin_name = me;
END $$;

GRANT EXECUTE ON FUNCTION admin_login(TEXT, TEXT), admin_logout(), admin_whoami(),
  admin_save_users(JSON, JSON, JSON), admin_update_self(TEXT, TEXT, TEXT),
  field_admin_name(), field_is_owner(), field_month_locked(DATE) TO anon, authenticated;

-- ---------------------------------------------------------------- row level security
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['field_workers', 'field_reports', 'field_leaves', 'field_settings',
                           'field_month_locks', 'field_finished_sites', 'field_homes'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "read all" ON %I', t);
    EXECUTE format('CREATE POLICY "read all" ON %I FOR SELECT USING (true)', t);
    EXECUTE format('DROP POLICY IF EXISTS "admin write" ON %I', t);
    IF t = 'field_settings' THEN
      -- the admin list itself only changes through admin_save_users / admin_update_self
      EXECUTE format('CREATE POLICY "admin write" ON %I FOR ALL USING (field_admin_name() IS NOT NULL AND key <> %L) WITH CHECK (field_admin_name() IS NOT NULL AND key <> %L)', t, 'admin_users', 'admin_users');
    ELSE
      EXECUTE format('CREATE POLICY "admin write" ON %I FOR ALL USING (field_admin_name() IS NOT NULL) WITH CHECK (field_admin_name() IS NOT NULL)', t);
    END IF;
  END LOOP;

  -- workers: their own reports and leaves, only in months that aren't locked
  FOREACH t IN ARRAY ARRAY['field_reports', 'field_leaves'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS "worker insert" ON %I', t);
    EXECUTE format('CREATE POLICY "worker insert" ON %I FOR INSERT WITH CHECK (NOT field_month_locked(date))', t);
    EXECUTE format('DROP POLICY IF EXISTS "worker update" ON %I', t);
    EXECUTE format('CREATE POLICY "worker update" ON %I FOR UPDATE USING (NOT field_month_locked(date)) WITH CHECK (NOT field_month_locked(date))', t);
    EXECUTE format('DROP POLICY IF EXISTS "worker delete" ON %I', t);
    EXECUTE format('CREATE POLICY "worker delete" ON %I FOR DELETE USING (NOT field_month_locked(date))', t);
  END LOOP;
END $$;
