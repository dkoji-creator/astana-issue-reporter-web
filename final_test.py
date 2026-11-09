"""Final test (Part A4): prints the results of the user test from the database.

Each tester signs up with their own e-mail and sends one report with a photo and a
description. The page measures the seconds from the first tap on the map to Submit and the
server saves them in reports.fill_seconds. This script reads them back:

    python3 final_test.py                      # every report that has a measured time
    python3 final_test.py "2026-11-10 09:00"   # only reports sent after this time (UTC)
"""
import os
import sqlite3
import sys
from pathlib import Path

TARGET_SECONDS = 120          # success criterion 1 (Stage 1, A3): "in under two minutes"

db = sqlite3.connect(os.environ.get("APP_DB", Path(__file__).parent / "app.db"))
since = sys.argv[1] if len(sys.argv) > 1 else "2000-01-01"

rows = db.execute(
    "SELECT u.display_name, u.email, r.id, r.photo_path IS NOT NULL, length(r.description), r.fill_seconds, "
    "r.created_at FROM reports r JOIN users u ON u.id = r.user_id "
    "WHERE r.fill_seconds IS NOT NULL AND r.created_at >= ? ORDER BY r.id", (since,)
).fetchall()

print("Criterion 1: a new report with a photo and a description in under 2 minutes\n")
print(f"{'tester':<20} {'report':>6} {'photo':>5} {'chars':>5} {'seconds':>8}  result")
for name, email, report_id, has_photo, chars, seconds, created in rows:
    ok = seconds < TARGET_SECONDS and has_photo
    print(f"{name[:20]:<20} {report_id:>6} {'yes' if has_photo else 'no':>5} {chars:>5} {seconds:>8.1f}  "
          f"{'MET' if ok else 'NOT MET'}")
if rows:
    times = [r[5] for r in rows]
    met = sum(1 for r in rows if r[5] < TARGET_SECONDS and r[3])
    print(f"\n{len(rows)} reports, mean {sum(times) / len(times):.1f} s, fastest {min(times):.1f} s, "
          f"slowest {max(times):.1f} s; {met} of {len(rows)} met the target")
else:
    print("(no measured reports yet)")

# criterion 3 can be checked on the same database at any moment
order = db.execute(
    "SELECT r.id, (SELECT COUNT(*) FROM votes v WHERE v.report_id = r.id) AS n FROM reports r "
    "ORDER BY n DESC, r.created_at DESC, r.id DESC").fetchall()
counts = [n for _, n in order]
print("\nCriterion 3: reports sorted by votes:", "MET" if counts == sorted(counts, reverse=True) else "NOT MET",
      f"({len(order)} reports, top 5 votes: {counts[:5]})")
