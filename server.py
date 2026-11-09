import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import ssl
import sys
import time
import uuid
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import mailer

BASE = Path(__file__).parent
# Final: every setting can come from the environment, so the same file runs on the laptop
# and on the public host (see README, "Public hosting")
DB_FILE = Path(os.environ.get("APP_DB", BASE / "app.db"))
PAGE_FILE = BASE / "index.html"
UPLOADS = Path(os.environ.get("APP_UPLOADS", BASE / "uploads"))
STATIC = BASE / "static"          # logo, icons, map, sound, video (Assignment 4)
MEDIA_SRC = BASE / "media_src"    # full-size originals, used only by the /before page

# file extension -> Content-Type for everything we serve as a file
MIME = {
    ".html": "text/html; charset=utf-8", ".svg": "image/svg+xml", ".webp": "image/webp",
    ".png": "image/png", ".jpg": "image/jpeg", ".mp3": "audio/mpeg", ".wav": "audio/wav",
    ".mp4": "video/mp4", ".webm": "video/webm", ".vtt": "text/vtt; charset=utf-8",
}
UPLOAD_TYPES = {"data:image/jpeg;base64": ".jpg", "data:image/png;base64": ".png",
                "data:image/webp;base64": ".webp"}

# The /before page is the same page with the unoptimised originals put back.
# It exists only to measure page weight before and after optimisation (Part B2).
BEFORE_SWAPS = {
    'srcset="/static/img/map-420.webp 420w, /static/img/map-840.webp 840w"': "",
    'src="/static/img/map-840.webp"': 'src="/media_src/map_original.png"',
    'poster="/static/media/howto-poster.webp"': 'poster="/media_src/howto-poster.png"',
    'preload="none"': 'preload="auto"',
    'src="/static/media/howto.mp4"': 'src="/media_src/howto_original.mp4"',
    '"/static/media/notify.mp3"': '"/media_src/notify.wav"',
}
STATUSES = {"under_review": "Under review", "in_progress": "In progress", "resolved": "Resolved"}
MAX_FAILED_LOGINS = 5            # Assignment 3, C1: lock the account after 5 wrong passwords
LOCK_SECONDS = 15 * 60           # ... for 15 minutes
MAX_REPORTS_PER_10_MIN = 5       # Assignment 3, C1: rate limit on the report form
SESSION_DAYS = 30
USE_HTTPS = "--https" in sys.argv
# behind a host that ends HTTPS for us (PythonAnywhere, Render): cookies get the Secure flag
# and HSTS is sent, although Python itself talks plain HTTP to the host's proxy
PUBLIC_HTTPS = USE_HTTPS or os.environ.get("PUBLIC_HTTPS") == "1"
HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8000"))


def get_db():
    db = sqlite3.connect(DB_FILE, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    return db


def column_exists(db, table, column):
    return any(row["name"] == column for row in db.execute(f"PRAGMA table_info({table})"))


# Brings any older app.db (Assignment 3, 4, Stage 2) up to the final schema, and creates
# a database with test data on the very first start (an empty public host has no app.db).
def prepare_database():
    if not DB_FILE.exists():
        import seed
        seed.build(DB_FILE)
    db = get_db()
    db.executescript((BASE / "migrations.sql").read_text(encoding="utf-8"))
    if not column_exists(db, "notifications", "email_status"):
        db.execute("ALTER TABLE notifications ADD COLUMN email_status TEXT")
    if not column_exists(db, "reports", "fill_seconds"):
        db.execute("ALTER TABLE reports ADD COLUMN fill_seconds REAL")
    db.execute("DELETE FROM sessions WHERE expires_at < datetime('now')")
    db.commit()
    db.close()


# the same hash format as in seed.py
def hash_password(password):
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 100_000)
    return "pbkdf2_sha256$100000$" + salt.hex() + "$" + digest.hex()


def verify_password(password, stored):
    algorithm, iterations, salt_hex, hash_hex = stored.split("$")
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), int(iterations))
    return hmac.compare_digest(digest.hex(), hash_hex)


class Handler(BaseHTTPRequestHandler):

    def send_bytes(self, code, body, content_type, headers=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("X-Content-Type-Options", "nosniff")
        if PUBLIC_HTTPS:
            self.send_header("Strict-Transport-Security", "max-age=31536000")
        self.end_headers()
        self.wfile.write(body)

    # sends a file from disk; supports "Range: bytes=..." because Safari needs it to play video
    def send_file(self, path, cache=True):
        body = path.read_bytes()
        headers = {"Accept-Ranges": "bytes"}
        if cache:
            headers["Cache-Control"] = "public, max-age=86400"
        kind = MIME.get(path.suffix, "application/octet-stream")
        ranges = self.headers.get("Range", "")
        if ranges.startswith("bytes=") and "," not in ranges:
            start, _, end = ranges[6:].partition("-")
            try:
                if start:
                    first, last = int(start), int(end) if end else len(body) - 1
                else:
                    first, last = len(body) - int(end), len(body) - 1
                last = min(last, len(body) - 1)
                if not 0 <= first <= last:
                    raise ValueError
            except ValueError:
                self.send_bytes(416, b"", kind, {"Content-Range": f"bytes */{len(body)}"})
                return
            headers["Content-Range"] = f"bytes {first}-{last}/{len(body)}"
            self.send_bytes(206, body[first:last + 1], kind, headers)
        else:
            self.send_bytes(200, body, kind, headers)

    # /static/img/logo.svg -> static/img/logo.svg, but never a file outside the folder
    def file_in(self, folder, prefix, path):
        target = (folder / path[len(prefix):]).resolve()
        return target if target.is_file() and target.is_relative_to(folder.resolve()) else None

    def send_json(self, code, data, headers=None):
        self.send_bytes(code, json.dumps(data).encode(), "application/json", headers)

    def read_json(self, limit):
        length = int(self.headers["Content-Length"])
        if length > limit:
            raise OverflowError
        return json.loads(self.rfile.read(length))

    def session_token(self):
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        return cookie["session"].value if "session" in cookie else None

    # who is logged in: a row from users, or None.
    # Final: sessions live in the table sessions (Stage 2 kept them in memory, so a restart
    # logged everybody out). The cookie holds a random token; the table holds only its
    # SHA-256 hash, so a copy of app.db does not let anyone log in as another user.
    def current_user(self):
        token = self.session_token()
        if not token:
            return None
        db = get_db()
        user = db.execute(
            "SELECT u.id, u.email, u.display_name, u.role FROM sessions s JOIN users u ON u.id = s.user_id "
            "WHERE s.token_hash = ? AND s.expires_at > datetime('now')",
            (hashlib.sha256(token.encode()).hexdigest(),),
        ).fetchone()
        db.close()
        return user

    def start_session(self, user):
        token = secrets.token_hex(32)
        db = get_db()
        db.execute(
            "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, datetime('now', ?))",
            (hashlib.sha256(token.encode()).hexdigest(), user["id"], f"+{SESSION_DAYS} days"),
        )
        db.commit()
        db.close()
        cookie = f"session={token}; HttpOnly; SameSite=Lax; Path=/; Max-Age={SESSION_DAYS * 86400}"
        if PUBLIC_HTTPS:
            cookie += "; Secure"   # the browser sends the cookie only over HTTPS
        self.send_json(200, {"id": user["id"], "email": user["email"],
                             "display_name": user["display_name"], "role": user["role"]},
                       {"Set-Cookie": cookie})

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            self.send_bytes(200, PAGE_FILE.read_bytes(), "text/html; charset=utf-8")
        elif path == "/before":
            page = PAGE_FILE.read_text(encoding="utf-8")
            for old, new in BEFORE_SWAPS.items():
                page = page.replace(old, new)
            self.send_bytes(200, page.encode(), "text/html; charset=utf-8")
        elif path.startswith("/static/") and self.file_in(STATIC, "/static/", path):
            self.send_file(self.file_in(STATIC, "/static/", path))
        elif path.startswith("/media_src/") and self.file_in(MEDIA_SRC, "/media_src/", path):
            self.send_file(self.file_in(MEDIA_SRC, "/media_src/", path))
        elif path == "/api/me":
            user = self.current_user()
            self.send_json(200, dict(user) if user else None)
        elif path == "/api/reports":
            user = self.current_user()
            me = user["id"] if user else 0
            db = get_db()
            rows = db.execute(
                """
                SELECT r.id,
                       r.lat,
                       r.lng,
                       r.description,
                       r.status,
                       r.photo_path,
                       r.created_at,
                       c.name                                                  AS category,
                       (SELECT COUNT(*) FROM votes v WHERE v.report_id = r.id) AS votes,
                       EXISTS(SELECT 1 FROM votes v
                              WHERE v.report_id = r.id AND v.user_id = ?)      AS voted,
                       r.user_id = ?                                           AS mine
                FROM reports r
                         JOIN categories c ON c.id = r.category_id
                ORDER BY votes DESC, r.created_at DESC, r.id DESC
                """,
                (me, me),
            ).fetchall()
            db.close()
            self.send_json(200, [dict(r) for r in rows])
        elif path == "/api/categories":
            db = get_db()
            rows = db.execute("SELECT id, name FROM categories ORDER BY id").fetchall()
            db.close()
            self.send_json(200, [dict(r) for r in rows])
        elif path == "/api/notifications":
            user = self.current_user()
            if user is None:
                self.send_json(401, {"error": "please log in first"})
                return
            db = get_db()
            rows = db.execute(
                "SELECT id, report_id, message, is_read, created_at FROM notifications "
                "WHERE user_id = ? ORDER BY id DESC LIMIT 20", (user["id"],)
            ).fetchall()
            db.close()
            self.send_json(200, [dict(r) for r in rows])
        elif path.startswith("/uploads/"):
            photo_file = UPLOADS / Path(path).name
            if photo_file.is_file():
                self.send_file(photo_file)
            else:
                self.send_json(404, {"error": "not found"})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/register":
            self.register()
        elif self.path == "/api/login":
            self.login()
        elif self.path == "/api/logout":
            token = self.session_token()
            if token:
                db = get_db()
                db.execute("DELETE FROM sessions WHERE token_hash = ?",
                           (hashlib.sha256(token.encode()).hexdigest(),))
                db.commit()
                db.close()
            self.send_json(200, {"ok": True},
                           {"Set-Cookie": "session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0"})
        elif self.path == "/api/reports":
            self.create_report()
        elif re.fullmatch(r"/api/reports/\d+/vote", self.path):
            self.vote(int(self.path.split("/")[3]))
        elif re.fullmatch(r"/api/reports/\d+/status", self.path):
            self.change_status(int(self.path.split("/")[3]))
        elif self.path == "/api/notifications/read":
            self.mark_notifications_read()
        else:
            self.send_json(404, {"error": "not found"})

    def register(self):
        try:
            data = self.read_json(10_000)
            email = str(data["email"]).strip().lower()
            password = str(data["password"])
            name = str(data["display_name"]).strip()
        except (KeyError, ValueError, TypeError, OverflowError):
            self.send_json(400, {"error": "invalid data"})
            return
        if "@" not in email or len(email) > 200:
            self.send_json(400, {"error": "invalid email"})
            return
        if len(password) < 8:
            self.send_json(400, {"error": "password must be at least 8 characters"})
            return
        if not 1 <= len(name) <= 50:
            self.send_json(400, {"error": "name must be 1-50 characters"})
            return
        db = get_db()
        try:
            cur = db.execute(
                "INSERT INTO users (email, password_hash, display_name) VALUES (?, ?, ?)",
                (email, hash_password(password), name),
            )
            db.commit()
        except sqlite3.IntegrityError:
            self.send_json(409, {"error": "this email is already registered"})
            return
        finally:
            db.close()
        self.start_session({"id": cur.lastrowid, "email": email, "display_name": name, "role": "resident"})

    def login(self):
        try:
            data = self.read_json(10_000)
            email = str(data["email"]).strip().lower()
            password = str(data["password"])
        except (KeyError, ValueError, TypeError, OverflowError):
            self.send_json(400, {"error": "invalid data"})
            return
        # Final: the counter of wrong passwords is a table (login_attempts), so a restart
        # of the server no longer resets the lock
        db = get_db()
        attempt = db.execute("SELECT failed, locked_until FROM login_attempts WHERE email = ?",
                             (email,)).fetchone()
        failed, locked_until = (attempt["failed"], attempt["locked_until"]) if attempt else (0, 0)
        if locked_until > time.time():
            db.close()
            minutes = int((locked_until - time.time()) // 60) + 1
            self.send_json(429, {"error": f"too many wrong passwords, try again in {minutes} min"})
            return
        user = db.execute(
            "SELECT id, email, password_hash, display_name, role FROM users WHERE email = ?", (email,)
        ).fetchone()
        if user is None or not verify_password(password, user["password_hash"]):
            failed += 1
            locked = failed >= MAX_FAILED_LOGINS
            db.execute(
                "INSERT INTO login_attempts (email, failed, locked_until) VALUES (?, ?, ?) "
                "ON CONFLICT(email) DO UPDATE SET failed = excluded.failed, locked_until = excluded.locked_until",
                (email, 0 if locked else failed, time.time() + LOCK_SECONDS if locked else 0),
            )
            db.commit()
            db.close()
            if locked:
                self.send_json(429, {"error": "too many wrong passwords, account locked for 15 min"})
            else:
                self.send_json(401, {"error": "wrong email or password"})
            return
        db.execute("DELETE FROM login_attempts WHERE email = ?", (email,))
        db.commit()
        db.close()
        self.start_session(user)

    def create_report(self):
        user = self.current_user()
        if user is None:
            self.send_json(401, {"error": "please log in first"})
            return
        db = None
        try:
            try:
                data = self.read_json(4_000_000)
            except OverflowError:
                self.send_json(413, {"error": "request too large"})
                return

            photo_name = None
            raw = None
            if data.get("photo"):
                header, encoded = data["photo"].split(",", 1)
                extension = UPLOAD_TYPES[header]
                raw = base64.b64decode(encoded)
                if len(raw) > 2_000_000:
                    raise ValueError("photo too large")
                photo_name = uuid.uuid4().hex + extension

            db = get_db()
            recent = db.execute(
                "SELECT COUNT(*) FROM reports WHERE user_id = ? AND created_at >= datetime('now', '-10 minutes')",
                (user["id"],),
            ).fetchone()[0]
            if recent >= MAX_REPORTS_PER_10_MIN:
                self.send_json(429, {"error": "too many reports, please wait 10 minutes"})
                return
            # final test (success criterion 1): seconds from the first tap on the map to Submit,
            # measured by the page; anything outside 0-3600 s is not a real measurement
            fill_seconds = data.get("fill_seconds")
            fill_seconds = float(fill_seconds) if isinstance(fill_seconds, (int, float)) else None
            if fill_seconds is not None and not 0 < fill_seconds < 3600:
                fill_seconds = None
            cur = db.execute(
                "INSERT INTO reports (user_id, category_id, description, lat, lng, photo_path, fill_seconds) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (user["id"], int(data["category_id"]), str(data["description"]).strip(),
                 float(data["lat"]), float(data["lng"]), photo_name, fill_seconds),
            )
            db.execute(
                "INSERT INTO status_log (report_id, changed_by, old_status, new_status) "
                "VALUES (?, ?, NULL, 'under_review')",
                (cur.lastrowid, user["id"]),
            )
            if photo_name:
                (UPLOADS / photo_name).write_bytes(raw)
            db.commit()
            self.send_json(201, {"id": cur.lastrowid})
        except (KeyError, ValueError, TypeError, AttributeError, sqlite3.IntegrityError):
            self.send_json(400, {"error": "invalid data"})
        finally:
            if db is not None:
                db.close()

    # R3: a resident likes a report (a second press takes the like back); one vote per user and report
    def vote(self, report_id):
        user = self.current_user()
        if user is None:
            self.send_json(401, {"error": "please log in first"})
            return
        db = get_db()
        try:
            if db.execute("SELECT 1 FROM reports WHERE id = ?", (report_id,)).fetchone() is None:
                self.send_json(404, {"error": "report not found"})
                return
            removed = db.execute("DELETE FROM votes WHERE user_id = ? AND report_id = ?",
                                 (user["id"], report_id)).rowcount
            if not removed:
                db.execute("INSERT INTO votes (user_id, report_id) VALUES (?, ?)", (user["id"], report_id))
            db.commit()
            votes = db.execute("SELECT COUNT(*) FROM votes WHERE report_id = ?", (report_id,)).fetchone()[0]
            self.send_json(200, {"voted": not removed, "votes": votes})
        finally:
            db.close()

    # R7 + R8: only an admin may change the status (role-based access control, Assignment 3);
    # the change is logged in status_log and the author of the report gets a notification
    def change_status(self, report_id):
        user = self.current_user()
        if user is None:
            self.send_json(401, {"error": "please log in first"})
            return
        if user["role"] != "admin":
            self.send_json(403, {"error": "only city service staff (admin) can change the status"})
            return
        try:
            new_status = str(self.read_json(1_000)["status"])
        except (KeyError, ValueError, TypeError, OverflowError):
            new_status = None
        if new_status not in STATUSES:
            self.send_json(400, {"error": "invalid status"})
            return
        db = get_db()
        try:
            report = db.execute("SELECT id, user_id, status FROM reports WHERE id = ?", (report_id,)).fetchone()
            if report is None:
                self.send_json(404, {"error": "report not found"})
                return
            if report["status"] != new_status:
                message = f"Your report #{report_id} is now: {STATUSES[new_status]}"
                db.execute("UPDATE reports SET status = ? WHERE id = ?", (new_status, report_id))
                db.execute(
                    "INSERT INTO status_log (report_id, changed_by, old_status, new_status) VALUES (?, ?, ?, ?)",
                    (report_id, user["id"], report["status"], new_status),
                )
                cur = db.execute(
                    "INSERT INTO notifications (user_id, report_id, message) VALUES (?, ?, ?)",
                    (report["user_id"], report_id, message),
                )
                db.commit()
                # R8 (final): the same message also goes to the author's e-mail, in the background,
                # so a slow mail server never delays the admin's answer
                author = db.execute("SELECT email, display_name FROM users WHERE id = ?",
                                    (report["user_id"],)).fetchone()
                mailer.send_in_background(DB_FILE, cur.lastrowid, author["email"], author["display_name"],
                                          report_id, message)
            self.send_json(200, {"id": report_id, "status": new_status})
        finally:
            db.close()

    def mark_notifications_read(self):
        user = self.current_user()
        if user is None:
            self.send_json(401, {"error": "please log in first"})
            return
        db = get_db()
        db.execute("UPDATE notifications SET is_read = 1 WHERE user_id = ?", (user["id"],))
        db.commit()
        db.close()
        self.send_json(200, {"ok": True})


UPLOADS.mkdir(parents=True, exist_ok=True)
prepare_database()


def main():
    # ThreadingHTTPServer: one slow client (a big photo on a weak 4G line) does not block the others
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    scheme = "http"
    if USE_HTTPS:
        # python3 server.py --https   needs cert.pem and key.pem (see README: one openssl command)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(BASE / "cert.pem", BASE / "key.pem")
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    shown = "127.0.0.1" if HOST in ("0.0.0.0", "") else HOST
    print(f"Server started: open {scheme}://{shown}:{PORT} in your browser")
    server.serve_forever()


if __name__ == "__main__":
    main()