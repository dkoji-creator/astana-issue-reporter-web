"""R8 (final): an e-mail copy of the notification when an admin changes the status.

With SMTP settings in the environment the letter is really sent (for example through a
Gmail account with an app password). Without them, on the laptop, the letter is saved as a
.eml file in the folder outbox/, so the demo works without the internet and every letter
can be opened in any mail program. The result is written to notifications.email_status.
"""
import os
import smtplib
import sqlite3
import threading
from email.message import EmailMessage
from pathlib import Path

OUTBOX = Path(os.environ.get("APP_OUTBOX", Path(__file__).parent / "outbox"))
SITE_URL = os.environ.get("SITE_URL", "http://127.0.0.1:8000")


def build_letter(to_email, to_name, report_id, text):
    letter = EmailMessage()
    letter["From"] = os.environ.get("MAIL_FROM", "Astana Issue Reporter <no-reply@astana-issue-reporter.local>")
    letter["To"] = to_email
    letter["Subject"] = f"Report #{report_id}: status changed"
    letter.set_content(
        f"Hello, {to_name}!\n\n{text}.\n\nOpen the map to see the report: {SITE_URL}\n\n"
        "You get this letter because you sent this report to Astana Issue Reporter.\n"
    )
    return letter


def deliver(letter):
    host = os.environ.get("SMTP_HOST")
    if not host:
        OUTBOX.mkdir(exist_ok=True)
        name = f"{letter['To']}_{letter['Subject'].split(':')[0].replace(' ', '').replace('#', '')}.eml"
        (OUTBOX / name).write_bytes(bytes(letter))
        return "saved"
    port = int(os.environ.get("SMTP_PORT", "587"))
    with smtplib.SMTP(host, port, timeout=15) as smtp:
        smtp.starttls()                      # the letter and the password travel encrypted (TLS)
        smtp.login(os.environ["SMTP_USER"], os.environ["SMTP_PASSWORD"])
        smtp.send_message(letter)
    return "sent"


def send_now(db_file, notification_id, to_email, to_name, report_id, text):
    try:
        status = deliver(build_letter(to_email, to_name, report_id, text))
    except (OSError, smtplib.SMTPException, KeyError):
        status = "failed"                    # the in-app notification is still there
    db = sqlite3.connect(db_file, timeout=10)
    db.execute("UPDATE notifications SET email_status = ? WHERE id = ?", (status, notification_id))
    db.commit()
    db.close()
    return status


def send_in_background(*args):
    threading.Thread(target=send_now, args=args, daemon=True).start()
