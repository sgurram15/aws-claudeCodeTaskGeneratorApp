# Task Tracker

A REST API for managing tasks, built with Flask and SQLite. Includes a single-page web frontend.

## Task Model

| Field       | Type   | Notes                              |
|-------------|--------|------------------------------------|
| id          | int    | Auto-generated                     |
| title       | string | Required                           |
| description | string | Optional                           |
| priority    | string | `low`, `medium`, or `high`         |
| status      | string | `open` or `done`                   |
| due_date    | string | Optional, format `YYYY-MM-DD`      |
| created_at  | string | Auto-generated ISO timestamp       |

## Setup

```bash
python -m venv .venv

# Windows
.venv/Scripts/pip install -r requirements.txt

# Linux / Mac
.venv/bin/pip install -r requirements.txt
```

## Running

```bash
python app.py
```

Open http://localhost:5000 in a browser to use the web frontend.

## API Endpoints

All endpoints return JSON. Errors return `{"error": "message"}` with status 400 or 404.

### List tasks

```
GET /api/tasks
```

### Create a task

```
POST /api/tasks
Content-Type: application/json

{
  "title": "Buy groceries",
  "description": "Milk, eggs, bread",
  "priority": "high",
  "due_date": "2025-03-01"
}
```

Only `title` is required. `priority` defaults to `medium`, `status` defaults to `open`.

### Get a task

```
GET /api/tasks/<id>
```

### Update a task

```
PUT /api/tasks/<id>
Content-Type: application/json

{
  "status": "done",
  "priority": "low"
}
```

Any subset of fields can be provided.

### Delete a task

```
DELETE /api/tasks/<id>
```

## Testing

```bash
# Windows
.venv/Scripts/python -m pytest tests/ -v

# Linux / Mac
.venv/bin/python -m pytest tests/ -v
```

The test suite contains 13 tests covering all API endpoints and error cases.

## Project Structure

```
app.py              Flask route handlers
db.py               SQLite data access (stdlib sqlite3, no ORM)
schema.sql          DDL for the tasks table
templates/index.html  Single-page frontend
static/style.css    Stylesheet
static/app.js       Frontend logic
tests/              Pytest suite
requirements.txt    Dependencies (flask, pytest)
```
