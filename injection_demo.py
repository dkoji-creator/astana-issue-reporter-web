import sqlite3

db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE reports (id INTEGER PRIMARY KEY, description TEXT)")
db.execute("INSERT INTO reports (description) VALUES ('Pothole'), ('Broken lamp')")

evil = "x' OR '1'='1"

unsafe_sql = "SELECT * FROM reports WHERE description = '" + evil + "'"
print("UNSAFE query: ", unsafe_sql)
print("UNSAFE result:", db.execute(unsafe_sql).fetchall())

print("SAFE result:  ", db.execute("SELECT * FROM reports WHERE description = ?", (evil,)).fetchall())