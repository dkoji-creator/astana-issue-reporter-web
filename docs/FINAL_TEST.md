# Final test protocol (Final Project, Part A4)

We re-test the three success criteria from Stage 1 (A3) exactly as written, with at least
three people who are not in our team, on the final version of the system.

| # | Success criterion (Stage 1) | Target | How it is measured |
|---|---|---|---|
| 1 | A user can create a new issue request with a photo and description in under two minutes | under 120 s, with a photo, for every tester | The page measures the time from the first tap on the map to a successful Submit and saves it in `reports.fill_seconds`; `python3 final_test.py` prints it. We also time it with a phone stopwatch as a cross-check |
| 2 | The system displays and functions on mobile screens 360 px wide | every tester finishes the task on a phone; no sideways scrolling; buttons at least 44 px | The tester's own phone (we write down the model and the screen width in CSS px from https://whatismyviewport.com), plus `node tests/check_360px.js` |
| 3 | Requests are correctly sorted in the database by the number of votes | the list order equals the vote counts in the database, for every tester's like | Each tester likes one report; we check the "Top reports" list and run `python3 final_test.py` (it compares the order with `COUNT(*)` from the table `votes`) |

## Before the session

1. Start the system (public link, or `HOST=0.0.0.0 python3 server.py` on the laptop and the
   phone in the same Wi-Fi). Note the time in UTC.
2. Print one copy of the sheet below per tester. Ask each tester for verbal consent: the test
   is anonymous, we write only first name, phone model and times, the photo must not show people.

## Task given to the tester (read it aloud, do not help)

> "Imagine you saw a broken streetlight near your building. Using your phone, open this site,
> create an account, and report the problem with a photo and a short description. Then find
> the report that has the most likes on the map and like it too. Say 'done' when you finish."

The observer starts the stopwatch on the first tap on the map and stops it on the green message.

## Sheet (one per tester)

| Field | Value |
|---|---|
| Tester (first name only), relation to team | |
| Phone model, browser | |
| Viewport width (CSS px) | |
| Stopwatch time, s | |
| Time saved by the page (`final_test.py`), s | |
| Photo attached? | yes / no |
| Horizontal scrolling or element cut off? | yes / no, where |
| Liked a report; "Top reports" updated correctly? | yes / no |
| Where the tester hesitated (observer notes) | |
| Tester's own comment | |

## After the session

```
python3 final_test.py "YYYY-MM-DD HH:MM"     # the UTC time noted before the session
node tests/check_360px.js                     # optional automatic check of criterion 2
```

Copy the numbers into the table in the report next to the Stage 2 results.
