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
