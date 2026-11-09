-- Data analysis (Stage 2 Part C, corrected for the Final): three questions, one query each.
-- Run:  python3 analysis/make_charts.py   (prints the results and draws one chart per question)
-- or open app.db in DB Browser for SQLite and run a query.

-- Q1. How are the reports spread over the four categories, and how many are in each status?
SELECT c.name AS category,
       SUM(r.status = 'under_review') AS under_review,
       SUM(r.status = 'in_progress')  AS in_progress,
       SUM(r.status = 'resolved')     AS resolved,
       COUNT(*)                       AS total
FROM reports r JOIN categories c ON c.id = r.category_id
GROUP BY c.name
ORDER BY total DESC;

-- Q2. Which unresolved reports have the most likes (the city service's work queue)?
SELECT r.id, c.name AS category, r.status, COUNT(v.user_id) AS votes, r.description
FROM reports r
     JOIN categories c ON c.id = r.category_id
     LEFT JOIN votes v ON v.report_id = r.id
WHERE r.status <> 'resolved'
GROUP BY r.id
ORDER BY votes DESC, r.created_at
LIMIT 10;

-- Q3. On which streets are most Roads & Potholes reports, and how many are still open?
WITH streets(name) AS (VALUES ('Abay Ave'), ('Mangilik El Ave'), ('Turan Ave'), ('Kabanbay Batyr Ave'),
                              ('Syganak St'), ('Tauelsizdik Ave'), ('Kenesary St'), ('Respublika Ave'),
                              ('Dostyk St'))
SELECT s.name AS street,
       COUNT(*) AS road_reports,
       SUM(r.status <> 'resolved') AS still_open
FROM reports r
     JOIN categories c ON c.id = r.category_id AND c.name = 'Roads & Potholes'
     JOIN streets s ON r.description LIKE '%' || s.name || '%'
GROUP BY s.name
ORDER BY road_reports DESC, s.name;
