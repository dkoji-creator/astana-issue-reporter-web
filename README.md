# Astana Issue Reporter

Final Project, ICT course, Astana IT University, group SE-2624.
Team: Seitkali Nurtas, Alikhanuly Semser, Aiboluly Aibar.

A resident marks a city problem (pothole, broken streetlight, overflowing bin) on the map of
Astana, adds a category, a description and a photo, and follows its status. City service staff
see the open problems sorted by the number of likes and change their status; the author gets a
notification in the app and by e-mail.

- **Public link:** see the line "Public link" in the final report (PythonAnywhere, HTTPS).
  How it is deployed: [docs/DEPLOY.md](docs/DEPLOY.md).
- **Stack:** Python 3 standard library only (`http.server`, `sqlite3`, `hashlib`, `smtplib`),
  SQLite database, one `index.html` page (HTML, CSS, JavaScript), no frameworks.

## Run it locally (Windows, macOS, Linux)

Needs Python 3.9 or newer. Nothing else to install.

```
git clone https://github.com/dkoji-creator/astana-issue-reporter-web.git
cd astana-issue-reporter-web
python3 server.py          # Windows: py server.py
```

Open http://127.0.0.1:8000. On the first start the server creates `app.db` with test data
(120 reports, 15 users). To start again from clean test data: `python3 seed.py`.

To open the site from a phone in the same Wi-Fi: `HOST=0.0.0.0 python3 server.py`
(Windows PowerShell: `$env:HOST="0.0.0.0"; py server.py`), then open `http://<laptop IP>:8000`.

## Test accounts (every role)

All test accounts have the password **`Pass1234!`**.

| Role | Account | What it can do |
|---|---|---|
| Resident (user group 1) | `user2@example.kz` … `user15@example.kz` | Report a problem with a photo, like reports, follow the status in **My reports**, read **Alerts** |
| City service / admin (user group 2) | `user1@example.kz` | Everything a resident can, plus the **City service dashboard**: filter, sort by votes, change the status |
| New resident | sign up on the first screen | Same as a resident |

## Run the automatic tests

```
python3 -m unittest -v
```

The tests start their own server with a temporary copy of the database (your `app.db` is not
touched) and check every requirement that can be checked automatically: R1–R11, the three
success criteria where possible (sorting by votes), the security measures, and that logins and
the password lock survive a restart.

## Privacy, backups and the smart extension

- **Photo consent.** At sign-up a resident chooses whether other residents may see their
  photos. Without consent only the author and the city service see them.
- **Backups.** `python3 backup.py` writes a checked copy of the database to `backups/` and keeps
  the newest 14. How to run it every night (Windows Task Scheduler or the PythonAnywhere Tasks
  tab) is written at the top of the file. Restore: stop the server, copy a backup over `app.db`.
- **Smart bins (simulated IoT).** Six trash bins have a (simulated) fill-level sensor. Each
  sensor sends `{"bin_id", "fill_level", "battery", "temperature"}` to `POST /api/sensor/reading`
  with the header `X-Sensor-Key`. At 90 % the server opens a Trash report on the map by itself;
  when the bin is emptied (under 20 %) the report is resolved. The admin sees all bins in the
  dashboard. Try it with the server running:
  ```
  python3 simulate_sensor.py
  ```
  On the laptop the key is `local-test-key`; on the public host set `SENSOR_KEY` (a long random
  string) in the WSGI file, otherwise the endpoint answers 503.
- **Data analysis.** `analysis/queries.sql` holds the three questions from the report;
  `python3 analysis/make_charts.py` (needs `pip install matplotlib`) prints the answers and draws
  the charts in `analysis/charts/`.

## Final user test (success criteria)

The protocol is in [docs/FINAL_TEST.md](docs/FINAL_TEST.md). The page measures how long each
tester needs from the first tap on the map to Submit; `python3 final_test.py` prints the
results, and `node tests/check_360px.js` checks the 360 px criterion automatically.

## What each file does

| Path | What it is |
|---|---|
| `server.py` | Web server and API. Run it on the laptop |
| `wsgi.py` | The same server for public hosting (PythonAnywhere) |
| `mailer.py` | R8: e-mail copy of the status notification (SMTP, or a `.eml` file in `outbox/`) |
| `index.html` | The whole interface (HTML, CSS, JavaScript) |
| `schema.sql` | Database schema (tables, keys, CHECK rules) |
| `migrations.sql` | Brings an older `app.db` up to the final schema on start |
| `seed.py` | Test data (fixed random seed and date, so the charts in the report repeat) |
| `show_db.py` | `python3 show_db.py 121` prints every row the database holds for report #121 |
| `check_password.py`, `injection_demo.py` | Assignment 3 evidence: hashed passwords, why we use `?` in SQL |
| `tests/test_api.py` | Automatic tests |
| `final_test.py`, `tests/check_360px.js` | Final user test: times per tester, 360 px check |
| `backup.py` | Daily database backup with integrity check |
| `simulate_sensor.py` | Plays six bin sensors (smart extension) |
| `analysis/` | SQL queries and charts of the data analysis |
| `static/` | Logo, icon set, map picture, how-to video with captions, sound (Assignment 4) |
| `media_src/` | Originals and the scripts that made every media file (all own work) |
| `docs/` | Deployment guide |

## Security in short

- Passwords: PBKDF2-SHA256, 100,000 iterations, random 16-byte salt (`check_password.py`).
- SQL: only parameterised queries (`injection_demo.py` shows why).
- Access: only the admin role can change a status (HTTP 403 for a resident, 401 without login).
- 5 wrong passwords lock the account for 15 minutes; at most 5 reports per user in 10 minutes.
- Sessions: random 256-bit token in an HttpOnly, SameSite=Lax cookie (Secure on HTTPS); the
  database keeps only the SHA-256 of the token.
- HTTPS: on the public host the certificate comes from the host. On the laptop:
  `openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"`
  then `python3 server.py --https` and open https://127.0.0.1:8000.

## Settings (environment variables, all optional)

| Variable | Default | Meaning |
|---|---|---|
| `HOST`, `PORT` | `127.0.0.1`, `8000` | Where `server.py` listens |
| `APP_DB`, `APP_UPLOADS` | `app.db`, `uploads/` | Database file and photo folder |
| `PUBLIC_HTTPS` | off (`1` in `wsgi.py`) | Secure cookie and HSTS when the host serves HTTPS |
| `SITE_URL` | `http://127.0.0.1:8000` | Link inside the e-mails |
| `SENSOR_KEY` | `local-test-key` on the laptop, none on the host | Shared secret of the bin sensors |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM` | not set | Real e-mail; without them letters are saved to `outbox/` |

## Measuring the page (Assignment 4, R10)

`http://127.0.0.1:8000/before` is the same page with the unoptimised original media; it exists
only to compare page weight in DevTools. `node media_src/measure_network.js /` measures the
final page (needs Node.js with Playwright).
