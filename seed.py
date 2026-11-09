import hashlib
import os
import random
import sqlite3
from pathlib import Path

BASE = Path(__file__).parent
DB_FILE = BASE / "app.db"
SCHEMA_FILE = BASE / "schema.sql"


def hash_password(password):
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 100_000)
    return "pbkdf2_sha256$100000$" + salt.hex() + "$" + digest.hex()


def build(db_file=DB_FILE):
    # 1. Delete the old database, so this script can be run many times
    if db_file.exists():
        db_file.unlink()

    # 2. Create a new database from schema.sql
    db = sqlite3.connect(db_file)
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript(SCHEMA_FILE.read_text(encoding="utf-8"))

    rnd = random.Random(42)

    # 3. Categories
    for name in ["Roads & Potholes", "Lighting", "Landscaping", "Trash"]:
        db.execute("INSERT INTO categories (name) VALUES (?)", (name,))

    # 4. Users: user1 is admin, others are residents (password for all: Pass1234!)
    for i in range(1, 16):
        role = "admin" if i == 1 else "resident"
        db.execute(
            "INSERT INTO users (email, password_hash, display_name, role) VALUES (?, ?, ?, ?)",
            (f"user{i}@example.kz", hash_password("Pass1234!"),
             "City Service (admin)" if i == 1 else f"Resident {i}", role),
        )

    # 5. Reports
    streets = ["Abay Ave", "Mangilik El Ave", "Turan Ave", "Kabanbay Batyr Ave",
               "Syganak St", "Tauelsizdik Ave", "Kenesary St", "Respublika Ave", "Dostyk St"]
    templates = {
        1: ["Deep pothole on {street}, cars swerve to avoid it",
            "Cracked asphalt near the crossing on {street}",
            "Sunken manhole cover on {street}"],
        2: ["Streetlight not working on {street}, dark at night",
            "Flickering lamp near the bus stop on {street}"],
        3: ["Broken bench in the courtyard on {street}",
            "Fallen tree branch blocking the path on {street}"],
        4: ["Overflowing trash bin near {street}",
            "Illegal dump behind the building on {street}"],
    }
    statuses = ["under_review", "in_progress", "resolved"]

    for _ in range(120):
        category_id = rnd.randint(1, 4)
        description = rnd.choice(templates[category_id]).format(street=rnd.choice(streets))
        status = rnd.choices(statuses, weights=[5, 3, 2])[0]
        # test data: reports are spread over the 8 weeks before 01.11.2026 12:08 UTC (fixed date, so
        # re-running seed.py always gives the same data and the same Part C charts)
        age_hours = rnd.randint(2, 56 * 24)
        created = f"-{age_hours} hours"
        author = rnd.randint(2, 15)
        cur = db.execute(
            "INSERT INTO reports (user_id, category_id, description, lat, lng, status, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, datetime('2026-11-01 12:08:00', ?))",
            (author, category_id, description,
             round(rnd.uniform(51.10, 51.18), 6), round(rnd.uniform(71.38, 71.48), 6), status, created),
        )
        db.execute(
            "INSERT INTO status_log (report_id, changed_by, old_status, new_status, changed_at) "
            "VALUES (?, ?, NULL, 'under_review', datetime('2026-11-01 12:08:00', ?))",
            (cur.lastrowid, author, created),
        )
        if status != "under_review":
            changed = f"-{rnd.randint(1, age_hours - 1)} hours"
            db.execute(
                "INSERT INTO status_log (report_id, changed_by, old_status, new_status, changed_at) "
                "VALUES (?, 1, 'under_review', ?, datetime('2026-11-01 12:08:00', ?))",
                (cur.lastrowid, status, changed),
            )

    # 6. Votes: 60 different pairs (user, report)
    pairs = rnd.sample([(u, r) for u in range(2, 16) for r in range(1, 41)], 60)
    db.executemany("INSERT INTO votes (user_id, report_id) VALUES (?, ?)", pairs)

    db.commit()
    db.close()
    print("Database", db_file.name, "created")


if __name__ == "__main__":
    build()
