import hashlib
import hmac
import sqlite3
from pathlib import Path

DB_FILE = Path(__file__).parent / "app.db"


def verify_password(password, stored):
    algorithm, iterations, salt_hex, hash_hex = stored.split("$")
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), int(iterations))
    return hmac.compare_digest(digest.hex(), hash_hex)


db = sqlite3.connect(DB_FILE)
stored = db.execute("SELECT password_hash FROM users WHERE email = ?", ("user2@example.kz",)).fetchone()[0]
print("Stored in database:", stored[:60] + "...")
print("Correct password:", verify_password("Pass1234!", stored))
print("Wrong password:  ", verify_password("wrong", stored))