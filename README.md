# Astana Issue Reporter — prototype (Project Stage 2, End-term)

A resident marks a city problem on the map of Astana, adds a category, a description and a photo,
and sends it. Reports are stored in SQLite and shown as coloured markers, sorted by votes.

## How to run

Needs only Python 3.9 or newer (no packages to install).

```
python3 seed.py      # optional: rebuilds app.db with 120 test reports
python3 server.py    # then open http://127.0.0.1:8000
```

Test account: `user2@example.kz`, password `Pass1234!` (all test users have this password,
`user1@example.kz` is the admin).

On Windows use `py seed.py` and `py server.py` instead of `python3`.

### What each user group can do (Stage 2)

- **Resident:** sign up / log in, tap the map, choose a category, describe, add a photo, **Submit Report**;
  follow the status in **My reports**; like other reports (**Like (+1)**, one like per user);
  read the **Alerts** (in-app notifications when the city service changes the status).
- **City service (admin, `user1@example.kz`):** the **City service dashboard** lists reports sorted by votes
  (or newest first) with a status filter; open a report, choose a new status, **Save status**.
  The change is written to `status_log` and the author gets a notification.

`python3 show_db.py 121` prints what the database holds for report #121 (report, likes, status history,
notifications) — useful to show where a value on the screen is stored.

### Security (Assignment 3 measures)

- Passwords: PBKDF2-SHA256, 100,000 iterations, random salt (`check_password.py` shows it).
- SQL: only parameterised queries (`injection_demo.py` shows why).
- Access rules: only an admin can change a status (HTTP 403 for residents, 401 without login).
- 5 wrong passwords lock the account for 15 minutes; at most 5 reports per user in 10 minutes.
- HTTPS: create a certificate once, then start with `--https` and open https://127.0.0.1:8000

```
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
python3 server.py --https
```

The certificate is self-signed, so the browser shows a warning once ("Advanced → Proceed").
On public hosting a real certificate (e.g. Let's Encrypt) replaces it.

- Read: the map, the details card and the "Top reports" list load from `/api/reports`.
- Write: log in, tap the map, choose a category, write a description, optionally add a photo,
  press **Submit Report**.

`http://127.0.0.1:8000/before` is the same page with the unoptimised original media
(3360 px PNG map, PNG poster, WAV sound, near-lossless video loaded at once). It exists only
to measure page weight before and after optimisation in DevTools.

## Files

| Path | What it is |
|---|---|
| `server.py` | Web server and API (Python `http.server`), serves `static/` and `uploads/` |
| `show_db.py` | Prints the database rows of one report (Stage 2 evidence) |
| `index.html` | The whole interface (HTML, CSS, JavaScript) |
| `schema.sql`, `seed.py`, `app.db` | Database schema, test data, the database |
| `static/img/` | `logo.svg`, `icons.svg` (icon set), `map-420.webp`, `map-840.webp` |
| `static/media/` | `howto.mp4` (how-to clip), `howto.en.vtt` (captions), `howto-poster.webp`, `notify.mp3` |
| `media_src/` | Originals and the scripts that made every media file (all own work) |
| `uploads/` | Photos sent with reports (converted to WebP in the browser) |

## Rebuilding the media (optional)

Needs Python with Pillow, ffmpeg, and Node.js with Playwright. Start `server.py`, then:

```
sh media_src/build_media.sh                       # map, sound, how-to video, poster
python3 media_src/image_experiment.py shot.png out  # Part A2: one screenshot in 5 formats
node media_src/measure_network.js /before          # Part B2: page weight before
node media_src/measure_network.js /                # Part B2: page weight after
```
