# Shows what the database holds for one report: the report, its likes, its status history
# and the notifications of its author.   python3 show_db.py 121
import os
import sqlite3
import sys
from pathlib import Path

db = sqlite3.connect(os.environ.get("APP_DB", Path(__file__).parent / "app.db"))
report_id = int(sys.argv[1]) if len(sys.argv) > 1 else db.execute("SELECT MAX(id) FROM reports").fetchone()[0]


def show(title, sql, args=()):
    cur = db.execute(sql, args)
    print("\n" + title)
    print(" | ".join(d[0] for d in cur.description))
    for row in cur.fetchall():
        print(" | ".join(str(v) for v in row))


show("reports", "SELECT r.id, u.email AS author, c.name AS category, r.description, r.lat, r.lng, "
     "r.photo_path, r.status, r.created_at FROM reports r JOIN users u ON u.id = r.user_id "
     "JOIN categories c ON c.id = r.category_id WHERE r.id = ?", (report_id,))
show("votes", "SELECT v.report_id, u.email AS voter FROM votes v JOIN users u ON u.id = v.user_id "
     "WHERE v.report_id = ?", (report_id,))
show("status_log", "SELECT s.id, s.old_status, s.new_status, u.email AS changed_by, s.changed_at "
     "FROM status_log s JOIN users u ON u.id = s.changed_by WHERE s.report_id = ? ORDER BY s.id", (report_id,))
show("notifications", "SELECT n.id, u.email AS to_user, n.message, n.is_read, n.email_status, n.created_at "
     "FROM notifications n JOIN users u ON u.id = n.user_id WHERE n.report_id = ?", (report_id,))
