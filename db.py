import os
import sqlite3

from flask import g, current_app


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(current_app.config["DATABASE"])
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


def close_db(e=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db(app):
    with app.app_context():
        conn = sqlite3.connect(app.config["DATABASE"])
        schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
        with open(schema_path) as f:
            conn.executescript(f.read())
        conn.close()


def init_app(app):
    init_db(app)
    app.teardown_appcontext(close_db)


def list_tasks():
    rows = get_db().execute("SELECT * FROM tasks ORDER BY created_at DESC").fetchall()
    return [dict(row) for row in rows]


def get_task(task_id):
    row = get_db().execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return dict(row) if row else None


def create_task(title, description, priority, due_date):
    db = get_db()
    cursor = db.execute(
        "INSERT INTO tasks (title, description, priority, due_date) VALUES (?, ?, ?, ?)",
        (title, description, priority, due_date),
    )
    db.commit()
    return get_task(cursor.lastrowid)


def update_task(task_id, **fields):
    if not fields:
        return get_task(task_id)
    allowed = {"title", "description", "priority", "status", "due_date"}
    fields = {k: v for k, v in fields.items() if k in allowed}
    if not fields:
        return get_task(task_id)
    set_clause = ", ".join(f"{k} = ?" for k in fields)
    values = list(fields.values()) + [task_id]
    db = get_db()
    db.execute(f"UPDATE tasks SET {set_clause} WHERE id = ?", values)
    db.commit()
    return get_task(task_id)


def delete_task(task_id):
    db = get_db()
    cursor = db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    db.commit()
    return cursor.rowcount > 0
