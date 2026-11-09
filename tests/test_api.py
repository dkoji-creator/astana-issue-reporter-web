"""Automatic tests of the final system (Final Project, Part A1 and A4).

Run from the project folder:   python3 -m unittest -v
Every test class starts its own server on a free port with a fresh copy of the test
database, so the real app.db is never touched. Only the Python standard library is used.
"""
import http.cookiejar
import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASSWORD = "Pass1234!"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Client:
    """A browser in miniature: keeps the session cookie between requests."""

    def __init__(self, base):
        self.base = base
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, data=None):
        body = json.dumps(data).encode() if data is not None else None
        request = urllib.request.Request(self.base + path, data=body, method=method,
                                         headers={"Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=10) as response:
                return response.status, json.loads(response.read() or b"null")
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read() or b"null")

    def login(self, email, password=PASSWORD):
        return self.call("POST", "/api/login", {"email": email, "password": password})


class ServerTest(unittest.TestCase):
    env_extra = {}
    script = "server.py"

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.db_file = Path(cls.tmp.name) / "test.db"
        cls.port = free_port()
        cls.env = dict(os.environ, APP_DB=str(cls.db_file), APP_UPLOADS=str(Path(cls.tmp.name) / "uploads"),
                       PORT=str(cls.port), HOST="127.0.0.1",
                       APP_OUTBOX=str(Path(cls.tmp.name) / "outbox"), **cls.env_extra)
        cls.env.pop("SMTP_HOST", None)
        cls.start_server()

    @classmethod
    def start_server(cls):
        cls.proc = subprocess.Popen([sys.executable, str(ROOT / cls.script)], cwd=ROOT, env=cls.env,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                with socket.create_connection(("127.0.0.1", cls.port), timeout=0.2):
                    return
            except OSError:
                time.sleep(0.1)
        raise RuntimeError("server did not start")

    @classmethod
    def stop_server(cls):
        cls.proc.terminate()
        cls.proc.wait(timeout=10)

    @classmethod
    def tearDownClass(cls):
        cls.stop_server()
        cls.tmp.cleanup()

    def client(self):
        return Client(f"http://127.0.0.1:{self.port}")

    def query(self, sql, args=()):
        db = sqlite3.connect(self.db_file)
        rows = db.execute(sql, args).fetchall()
        db.close()
        return rows

    def new_report(self, client, **extra):
        data = {"category_id": 1, "description": "Test pothole near the stop", "lat": 51.15, "lng": 71.43}
        data.update(extra)
        return client.call("POST", "/api/reports", data)


class ResidentJourney(ServerTest):
    """User group 1: sign up, report, like, see the status (R1-R6, R9)."""

    def test_sign_up_and_report_is_saved(self):
        c = self.client()
        code, me = c.call("POST", "/api/register",
                          {"email": "tester@example.kz", "password": "Secret123", "display_name": "Tester"})
        self.assertEqual(code, 200)
        self.assertEqual(me["role"], "resident")
        code, result = self.new_report(c, lat=51.14819, lng=71.425417)
        self.assertEqual(code, 201)
        row = self.query("SELECT lat, lng, status FROM reports WHERE id = ?", (result["id"],))[0]
        self.assertEqual(row, (51.14819, 71.425417, "under_review"))          # R1, R6

    def test_report_with_photo(self):
        c = self.client()
        c.login("user5@example.kz")
        pixel = ("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8"
                 "/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")
        code, result = self.new_report(c, photo=pixel)
        self.assertEqual(code, 201)
        name = self.query("SELECT photo_path FROM reports WHERE id = ?", (result["id"],))[0][0]
        self.assertTrue(name.endswith(".png"))                                   # R2

    def test_invalid_reports_are_refused(self):
        c = self.client()
        self.assertEqual(self.new_report(c)[0], 401)                             # not logged in
        c.login("user6@example.kz")
        self.assertEqual(self.new_report(c, description="abc")[0], 400)          # R5: min 5 characters
        self.assertEqual(self.new_report(c, lat=48.0)[0], 400)                   # outside Astana
        self.assertEqual(self.new_report(c, category_id=99)[0], 400)             # R4: unknown category

    def test_like_once_and_take_back(self):
        c = self.client()
        c.login("user7@example.kz")
        before = self.query("SELECT COUNT(*) FROM votes WHERE report_id = 90")[0][0]
        code, result = c.call("POST", "/api/reports/90/vote")
        self.assertEqual((code, result["voted"], result["votes"]), (200, True, before + 1))   # R3
        code, result = c.call("POST", "/api/reports/90/vote")
        self.assertEqual((result["voted"], result["votes"]), (False, before))

    def test_reports_sorted_by_votes(self):
        # success criterion 3: requests are sorted by the number of votes
        code, reports = self.client().call("GET", "/api/reports")
        self.assertEqual(code, 200)
        self.assertGreaterEqual(len(reports), 100)                               # R10: 100+ markers
        votes = [r["votes"] for r in reports]
        self.assertEqual(votes, sorted(votes, reverse=True))
        counted = dict(self.query("SELECT report_id, COUNT(*) FROM votes GROUP BY report_id"))
        for r in reports:
            self.assertEqual(r["votes"], counted.get(r["id"], 0))

    def test_fill_time_is_saved(self):
        # final test, criterion 1: the page sends the measured seconds with the report
        c = self.client()
        c.login("user13@example.kz")
        good = self.new_report(c, fill_seconds=47.3)[1]["id"]
        bad = self.new_report(c, fill_seconds=-5)[1]["id"]
        self.assertEqual(self.query("SELECT fill_seconds FROM reports WHERE id IN (?, ?) ORDER BY id",
                                    (good, bad)), [(47.3,), (None,)])

    def test_rate_limit(self):
        c = self.client()
        c.login("user8@example.kz")
        codes = [self.new_report(c)[0] for _ in range(6)]
        self.assertEqual(codes, [201] * 5 + [429])


class CityServiceJourney(ServerTest):
    """User group 2: dashboard, status change, notification + e-mail (R7, R8)."""

    def test_only_admin_changes_status(self):
        resident = self.client()
        resident.login("user2@example.kz")
        self.assertEqual(resident.call("POST", "/api/reports/5/status", {"status": "resolved"})[0], 403)
        self.assertEqual(self.client().call("POST", "/api/reports/5/status", {"status": "resolved"})[0], 401)

    def test_status_change_logs_and_notifies_author(self):
        author = self.client()
        author.login("user9@example.kz")
        report_id = self.new_report(author)[1]["id"]
        admin = self.client()
        self.assertEqual(admin.login("user1@example.kz")[1]["role"], "admin")
        code, _ = admin.call("POST", f"/api/reports/{report_id}/status", {"status": "in_progress"})
        self.assertEqual(code, 200)
        self.assertEqual(self.query("SELECT new_status FROM status_log WHERE report_id = ? ORDER BY id",
                                    (report_id,)), [("under_review",), ("in_progress",)])      # R7
        code, items = author.call("GET", "/api/notifications")
        self.assertEqual(items[0]["message"], f"Your report #{report_id} is now: In progress")   # R8
        for _ in range(50):          # the e-mail copy is made in the background
            status = self.query("SELECT email_status FROM notifications WHERE report_id = ?", (report_id,))
            if status[0][0]:
                break
            time.sleep(0.1)
        self.assertEqual(status[0][0], "saved")      # no SMTP in tests -> letter saved to outbox/


class SecurityAfterRestart(ServerTest):
    """Final fixes: logins and the password lock survive a restart (R11 and Assignment 3)."""

    def test_passwords_are_hashed(self):
        stored = self.query("SELECT password_hash FROM users WHERE email = 'user2@example.kz'")[0][0]
        self.assertTrue(stored.startswith("pbkdf2_sha256$100000$"))              # R11
        self.assertNotIn(PASSWORD, stored)

    def test_session_and_lock_survive_restart(self):
        c = self.client()
        c.login("user10@example.kz")
        codes = [self.client().login("user11@example.kz", "wrong-password")[0] for _ in range(5)]
        self.assertEqual(codes, [401, 401, 401, 401, 429])
        tokens = self.query("SELECT token_hash FROM sessions")
        self.assertTrue(all(len(t[0]) == 64 for t in tokens))                    # only hashes stored
        type(self).stop_server()
        type(self).start_server()
        code, me = c.call("GET", "/api/me")
        self.assertEqual(me["email"], "user10@example.kz")                       # still logged in
        self.assertEqual(self.client().login("user11@example.kz")[0], 429)       # still locked


class PrivacyBackupAndSensors(ServerTest):
    """Aibar's final features: photo consent, backup, smart bins."""

    def sensor(self, data, key="local-test-key"):
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}/api/sensor/reading", method="POST",
                                         data=json.dumps(data).encode(),
                                         headers={"Content-Type": "application/json", "X-Sensor-Key": key})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_photo_hidden_without_consent(self):
        pixel = ("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8"
                 "/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")
        author = self.client()
        author.call("POST", "/api/register", {"email": "shy@example.kz", "password": "Secret123",
                                              "display_name": "Shy", "photo_consent": False})
        report_id = self.new_report(author, photo=pixel)[1]["id"]

        def photo_seen_by(client):
            return next(r for r in client.call("GET", "/api/reports")[1] if r["id"] == report_id)["photo_path"]

        other = self.client()
        other.login("user3@example.kz")
        admin = self.client()
        admin.login("user1@example.kz")
        self.assertIsNone(photo_seen_by(other))          # another resident: no photo
        self.assertIsNotNone(photo_seen_by(author))      # the author sees it
        self.assertIsNotNone(photo_seen_by(admin))       # the city service sees it

    def test_backup_copy_is_complete(self):
        backups = Path(self.tmp.name) / "backups"
        env = dict(self.env, APP_BACKUPS=str(backups))
        out = subprocess.run([sys.executable, str(ROOT / "backup.py")], env=env, capture_output=True, text=True)
        self.assertIn("integrity ok", out.stdout)
        copy = sqlite3.connect(next(backups.glob("app-*.db")))
        self.assertEqual(copy.execute("SELECT COUNT(*) FROM users").fetchone(),
                         tuple(self.query("SELECT COUNT(*) FROM users")[0]))
        copy.close()

    def test_full_bin_opens_and_empty_bin_resolves_report(self):
        self.assertEqual(self.sensor({"bin_id": "B-02", "fill_level": 50}, key="wrong")[0], 401)
        self.assertEqual(self.sensor({"bin_id": "B-99", "fill_level": 50})[0], 404)
        self.assertEqual(self.sensor({"bin_id": "B-02", "fill_level": 150})[0], 400)
        code, result = self.sensor({"bin_id": "B-02", "fill_level": 93, "battery": 80})
        self.assertTrue(result["action"].startswith("report #"))
        report_id = int(result["action"].split("#")[1].split()[0])
        self.assertEqual(self.sensor({"bin_id": "B-02", "fill_level": 97})[1]["action"], "saved")   # no duplicate
        row = self.query("SELECT c.name, u.email, r.status FROM reports r JOIN categories c ON c.id = r.category_id "
                         "JOIN users u ON u.id = r.user_id WHERE r.id = ?", (report_id,))[0]
        self.assertEqual(row, ("Trash", "sensor@astana-issue-reporter.local", "under_review"))
        self.sensor({"bin_id": "B-02", "fill_level": 5})
        self.assertEqual(self.query("SELECT status FROM reports WHERE id = ?", (report_id,))[0][0], "resolved")
        self.assertEqual(self.client().login("sensor@astana-issue-reporter.local", "!")[0], 401)   # no login
        admin = self.client()
        admin.login("user1@example.kz")
        self.assertEqual(admin.call("GET", "/api/bins")[0], 200)
        resident = self.client()
        resident.login("user4@example.kz")
        self.assertEqual(resident.call("GET", "/api/bins")[0], 403)


class PublicHostingEntry(ServerTest):
    """wsgi.py (PythonAnywhere) gives the same answers as server.py."""
    script = "wsgi.py"

    def test_login_report_and_secure_cookie(self):
        base = f"http://127.0.0.1:{self.port}"
        request = urllib.request.Request(base + "/api/login", method="POST",
                                         data=json.dumps({"email": "user12@example.kz", "password": PASSWORD}).encode(),
                                         headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request) as response:
            self.assertEqual(json.loads(response.read())["role"], "resident")
            cookie = response.headers["Set-Cookie"]
            self.assertIn("Secure", cookie)          # the host serves HTTPS, so the cookie is Secure
            self.assertEqual(response.headers["Strict-Transport-Security"], "max-age=31536000")
        data = {"category_id": 2, "description": "Lamp is off at night", "lat": 51.12, "lng": 71.41}
        request = urllib.request.Request(base + "/api/reports", method="POST", data=json.dumps(data).encode(),
                                         headers={"Content-Type": "application/json",
                                                  "Cookie": cookie.split(";")[0]})
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 201)
        with urllib.request.urlopen(base + "/") as response:
            self.assertIn(b"Astana Issue Reporter", response.read())
        # the local test key for sensors is refused on the public host
        request = urllib.request.Request(base + "/api/sensor/reading", method="POST",
                                         data=b'{"bin_id": "B-01", "fill_level": 95}',
                                         headers={"Content-Type": "application/json", "X-Sensor-Key": "local-test-key"})
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request)
        self.assertEqual(caught.exception.code, 503)

if __name__ == "__main__":
    unittest.main()
