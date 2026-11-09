PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'resident' CHECK (role IN ('resident', 'admin')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Final (privacy): 1 = other residents may see this user's photos
  photo_consent INTEGER NOT NULL DEFAULT 1 CHECK (photo_consent IN (0, 1))
);

CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  description TEXT NOT NULL CHECK (length(description) BETWEEN 5 AND 500),
  lat REAL NOT NULL CHECK (lat BETWEEN 51.0 AND 51.3),
  lng REAL NOT NULL CHECK (lng BETWEEN 71.2 AND 71.7),
  photo_path TEXT,
  status TEXT NOT NULL DEFAULT 'under_review'
    CHECK (status IN ('under_review', 'in_progress', 'resolved')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Final test: seconds from the first tap on the map to Submit (success criterion 1)
  fill_seconds REAL
);

CREATE TABLE votes (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id INTEGER NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, report_id)
);

CREATE TABLE status_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  report_id INTEGER NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  changed_by INTEGER NOT NULL REFERENCES users(id),
  old_status TEXT,
  new_status TEXT NOT NULL,
  changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Stage 2: in-app notification to the author when an admin changes the status (R8)
CREATE TABLE notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id INTEGER NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Final (R8): what happened to the e-mail copy: sent, saved (to outbox/), failed
  email_status TEXT
);

-- Final: sessions and the login lock are kept in the database (see migrations.sql)
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL
);

CREATE TABLE login_attempts (
  email TEXT PRIMARY KEY,
  failed INTEGER NOT NULL DEFAULT 0,
  locked_until REAL NOT NULL DEFAULT 0
);

-- Final, smart extension: simulated fill-level sensors (rows for the bins: migrations.sql)
CREATE TABLE bins (
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

CREATE TABLE sensor_readings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bin_id TEXT NOT NULL REFERENCES bins(id) ON DELETE CASCADE,
  fill_level INTEGER NOT NULL CHECK (fill_level BETWEEN 0 AND 100),
  battery INTEGER CHECK (battery BETWEEN 0 AND 100),
  temperature REAL,
  received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
