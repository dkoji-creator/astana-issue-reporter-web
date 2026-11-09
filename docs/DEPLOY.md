# Public hosting on PythonAnywhere (free plan)

Why PythonAnywhere: it runs Python, keeps files on a real disk (our SQLite `app.db` and the
photos stay after a restart, unlike free container hosts), and serves the site over HTTPS with
its own certificate at `https://<username>.pythonanywhere.com`. The free plan needs no card.

## First deployment (about 10 minutes)

1. Sign up at https://www.pythonanywhere.com (Beginner account). The username becomes the address.
2. **Consoles → Bash**, then:
   ```
   git clone https://github.com/dkoji-creator/astana-issue-reporter-web.git
   cd astana-issue-reporter-web && python3 seed.py && python3 -m unittest
   ```
3. **Web → Add a new web app → Manual configuration → Python 3.10** (or newer).
4. On the Web tab open the **WSGI configuration file** link, delete everything in it and paste
   (replace `USERNAME`):
   ```python
   import os, sys
   path = "/home/USERNAME/astana-issue-reporter-web"
   sys.path.insert(0, path)
   os.chdir(path)
   os.environ["SITE_URL"] = "https://USERNAME.pythonanywhere.com"
   from wsgi import application
   ```
5. On the Web tab switch **Force HTTPS** on, then press **Reload**.
6. Open `https://USERNAME.pythonanywhere.com` and log in with a test account from the README.

## Update after a new commit

```
cd ~/astana-issue-reporter-web && git pull
```
then **Reload** on the Web tab.

## Optional: real e-mail (R8)

Without SMTP settings the letters are saved as `.eml` files in `outbox/` (open them with
**Files**). To really send them, create an app password for a Gmail account and add to the WSGI
file before the last line:
```python
os.environ["SMTP_HOST"] = "smtp.gmail.com"
os.environ["SMTP_PORT"] = "587"
os.environ["SMTP_USER"] = "team.account@gmail.com"
os.environ["SMTP_PASSWORD"] = "the 16-letter app password"
```
If sending fails, the in-app Alert still works and `notifications.email_status` becomes `failed`.

## Limits of the free plan (written in the report)

- One web worker: fine for a course demo, not for thousands of users.
- The site must be extended once every three months (button "Run until 3 months from today").
- The servers are outside Kazakhstan, so only test accounts and test data are kept there
  (see the report, section "Data and security", Law No. 94-V on data localisation).
