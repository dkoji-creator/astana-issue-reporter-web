-- Run by server.py on every start (CREATE ... IF NOT EXISTS changes nothing when the table
-- is already there). It brings an app.db from an earlier stage up to the final schema.

-- Stage 2: in-app notification to the author when an admin changes the status (R8)
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id INTEGER NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Final: logins survive a restart of the server (Stage 2 defect 3).
-- Only the SHA-256 of the cookie token is stored, never the token itself.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL
);

-- Final: the lock after 5 wrong passwords survives a restart too
CREATE TABLE IF NOT EXISTS login_attempts (
  email TEXT PRIMARY KEY,
  failed INTEGER NOT NULL DEFAULT 0,
  locked_until REAL NOT NULL DEFAULT 0
);

-- Final (Stage 2 plan item 8, Assignment 4 B1): a resident decides whether other residents
-- may see their photos. Old accounts keep 1 (test data); new sign-ups choose on the form.
-- (the column itself is added by server.py, because SQLite has no ADD COLUMN IF NOT EXISTS)

-- Final, smart extension (Stage 2 Part D): simulated fill-level sensors in trash bins.
-- A sensor never sees people; it sends only the bin id, fill level, battery and temperature.
CREATE TABLE IF NOT EXISTS bins (
  id TEXT PRIMARY KEY,                       -- printed on the bin, e.g. B-01
  address TEXT NOT NULL,
  lat REAL NOT NULL CHECK (lat BETWEEN 51.0 AND 51.3),
  lng REAL NOT NULL CHECK (lng BETWEEN 71.2 AND 71.7),
  fill_level INTEGER CHECK (fill_level BETWEEN 0 AND 100),
  battery INTEGER CHECK (battery BETWEEN 0 AND 100),
  temperature REAL,
  updated_at TEXT,
  open_report_id INTEGER REFERENCES reports(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS sensor_readings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bin_id TEXT NOT NULL REFERENCES bins(id) ON DELETE CASCADE,
  fill_level INTEGER NOT NULL CHECK (fill_level BETWEEN 0 AND 100),
  battery INTEGER CHECK (battery BETWEEN 0 AND 100),
  temperature REAL,
  received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO bins (id, address, lat, lng) VALUES
  ('B-01', 'Abay Ave 12', 51.1652, 71.4180),
  ('B-02', 'Kenesary St 40', 51.1600, 71.4310),
  ('B-03', 'Mangilik El Ave 55', 51.1210, 71.4450),
  ('B-04', 'Turan Ave 24', 51.1330, 71.4040),
  ('B-05', 'Dostyk St 5', 51.1280, 71.4300),
  ('B-06', 'Respublika Ave 33', 51.1700, 71.4400);

-- the account that the sensors' automatic reports are written under (reports.user_id is
-- NOT NULL). Its password hash is "!", which matches no password, so nobody can log in as it.
INSERT OR IGNORE INTO users (email, password_hash, display_name, role)
  VALUES ('sensor@astana-issue-reporter.local', '!', 'Smart bin sensor', 'resident');
