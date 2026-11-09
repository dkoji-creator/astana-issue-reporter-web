"""Daily backup of the database (Assignment 3 B3, Stage 2 plan item 7).

    python3 backup.py            -> backups/app-2026-11-09_0300.db, keeps the newest 14 copies

It uses SQLite's own backup function, so the copy is correct even while the server is
writing. Restore: stop the server, copy the wanted file over app.db, start the server.

Run it every night:
  Windows:      schtasks /create /tn "AstanaBackup" /sc daily /st 03:00 /tr "py C:\\astana-issue-reporter-web\\backup.py"
  PythonAnywhere: Tasks tab -> daily task:  python3 /home/USERNAME/astana-issue-reporter-web/backup.py
Then copy the backups/ folder to the team Google Drive once a week (the off-site copy).
"""
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).parent
DB_FILE = Path(os.environ.get("APP_DB", BASE / "app.db"))
BACKUPS = Path(os.environ.get("APP_BACKUPS", BASE / "backups"))
KEEP = 14


def make_backup():
    BACKUPS.mkdir(exist_ok=True)
    target = BACKUPS / f"app-{datetime.now(timezone.utc):%Y-%m-%d_%H%M%S}.db"
    source = sqlite3.connect(DB_FILE)
    copy = sqlite3.connect(target)
    source.backup(copy)
    # check the copy before trusting it
    ok = copy.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    reports = copy.execute("SELECT COUNT(*) FROM reports").fetchone()[0]
    copy.close()
    source.close()
    if not ok:
        target.unlink()
        sys.exit("backup failed the integrity check")
    old = sorted(BACKUPS.glob("app-*.db"))[:-KEEP]
    for file in old:
        file.unlink()
    print(f"{target.name}: {reports} reports, {target.stat().st_size // 1024} KB, integrity ok; "
          f"{len(old)} old copies removed")
    return target


if __name__ == "__main__":
    make_backup()
