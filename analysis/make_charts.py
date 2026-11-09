"""Runs the three queries in analysis/queries.sql on app.db, prints the results and draws one
chart per question into analysis/charts/ (black and white, so they print well).

    python3 analysis/make_charts.py            # needs: pip install matplotlib

The test data from seed.py is fixed (seed 42, date 01.11.2026), so the charts always repeat.
Use a fresh database (python3 seed.py) to get exactly the charts in the report.
"""
import os
import sqlite3
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).parent
DB_FILE = Path(os.environ.get("APP_DB", HERE.parent / "app.db"))
OUT = HERE / "charts"
OUT.mkdir(exist_ok=True)

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False,
                     "axes.spines.right": False})
queries = [q.strip() for q in (HERE / "queries.sql").read_text(encoding="utf-8").split(";") if "SELECT" in q]
db = sqlite3.connect(DB_FILE)


def run(sql):
    cur = db.execute(sql)
    names = [d[0] for d in cur.description]
    rows = cur.fetchall()
    print(" | ".join(names))
    for row in rows:
        print(" | ".join(str(v) for v in row))
    print()
    return rows


# Q1: stacked bars, status inside each category
print("Q1. Reports per category and status")
q1 = run(queries[0])
fig, ax = plt.subplots(figsize=(6.4, 3.4))
left = [0] * len(q1)
for i, (label, hatch, color) in enumerate([("Under review", "", "#222222"), ("In progress", "////", "#ffffff"),
                                           ("Resolved", "", "#bbbbbb")]):
    values = [row[1 + i] for row in q1]
    bars = ax.barh([row[0] for row in q1], values, left=left, color=color, edgecolor="black",
                   hatch=hatch, label=label)
    for bar, value in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_y() + bar.get_height() / 2, str(value),
                ha="center", va="center", color="white" if color == "#222222" else "black", fontsize=9,
                bbox=dict(facecolor="white", edgecolor="none", pad=1) if hatch else None)
    left = [a + b for a, b in zip(left, values)]
for y, total in enumerate(left):
    ax.text(total + 0.5, y, f"{total}", va="center", fontsize=9)
ax.invert_yaxis()
ax.set_xlabel("Number of reports")
ax.legend(ncol=3, loc="upper center", bbox_to_anchor=(0.5, -0.22), frameon=False)
fig.tight_layout()
fig.savefig(OUT / "q1_category_status.png", dpi=200)

# Q2: horizontal bars, top unresolved reports by votes
print("Q2. Top 10 unresolved reports by likes")
q2 = run(queries[1])
fig, ax = plt.subplots(figsize=(6.4, 3.6))
labels = [f"#{r[0]} {r[1]} ({'in progress' if r[2] == 'in_progress' else 'under review'})" for r in q2]
bars = ax.barh(labels, [r[3] for r in q2], color=["#222222" if r[2] == "under_review" else "#bbbbbb" for r in q2],
               edgecolor="black")
for bar, r in zip(bars, q2):
    ax.text(bar.get_width() + 0.05, bar.get_y() + bar.get_height() / 2, str(r[3]), va="center", fontsize=9)
ax.invert_yaxis()
ax.set_xlabel("Likes")
from matplotlib.patches import Patch  # noqa: E402
ax.legend(handles=[Patch(facecolor="#222222", edgecolor="black", label="Under review"),
                   Patch(facecolor="#bbbbbb", edgecolor="black", label="In progress")],
          loc="lower right", frameon=False)
ax.xaxis.get_major_locator().set_params(integer=True)
fig.tight_layout()
fig.savefig(OUT / "q2_top_unresolved.png", dpi=200)

# Q3: road reports per street, open part in black
print("Q3. Roads & Potholes reports per street")
q3 = run(queries[2])
fig, ax = plt.subplots(figsize=(6.4, 3.2))
streets = [r[0] for r in q3]
ax.barh(streets, [r[1] for r in q3], color="#ffffff", edgecolor="black", label="All road reports")
ax.barh(streets, [r[2] for r in q3], color="#222222", edgecolor="black", label="Still open")
for y, r in enumerate(q3):
    ax.text(r[1] + 0.05, y, f"{r[2]} of {r[1]} open", va="center", fontsize=9)
ax.invert_yaxis()
ax.set_xlabel("Number of Roads & Potholes reports")
ax.xaxis.get_major_locator().set_params(integer=True)
ax.legend(loc="lower right", frameon=False)
fig.tight_layout()
fig.savefig(OUT / "q3_road_streets.png", dpi=200)

print("Charts saved to", OUT)
sys.exit(0)
