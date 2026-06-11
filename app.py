import os
import re

from flask import Flask, jsonify, render_template, request

import db

app = Flask(__name__)
app.config["DATABASE"] = os.environ.get("DATABASE", os.path.join(os.path.dirname(__file__), "tasks.db"))

db.init_app(app)

PRIORITY_VALUES = {"low", "medium", "high"}
STATUS_VALUES = {"open", "done"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def validate_task_input(data, require_title=False):
    errors = []
    if require_title:
        title = data.get("title", "")
        if not isinstance(title, str) or not title.strip():
            errors.append("title is required")
    elif "title" in data:
        if not isinstance(data["title"], str) or not data["title"].strip():
            errors.append("title must be a non-empty string")

    if "priority" in data and data["priority"] not in PRIORITY_VALUES:
        errors.append(f"priority must be one of: {', '.join(sorted(PRIORITY_VALUES))}")

    if "status" in data and data["status"] not in STATUS_VALUES:
        errors.append(f"status must be one of: {', '.join(sorted(STATUS_VALUES))}")

    if "due_date" in data and data["due_date"] is not None:
        if not isinstance(data["due_date"], str) or not DATE_RE.match(data["due_date"]):
            errors.append("due_date must be in YYYY-MM-DD format")

    return errors


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/tasks", methods=["GET"])
def list_tasks():
    return jsonify(db.list_tasks())


@app.route("/api/tasks", methods=["POST"])
def create_task():
    data = request.get_json(force=True, silent=True) or {}
    errors = validate_task_input(data, require_title=True)
    if errors:
        return jsonify({"error": "; ".join(errors)}), 400

    task = db.create_task(
        title=data["title"].strip(),
        description=data.get("description", "").strip(),
        priority=data.get("priority", "medium"),
        due_date=data.get("due_date"),
    )
    return jsonify(task), 201


@app.route("/api/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    task = db.get_task(task_id)
    if not task:
        return jsonify({"error": "task not found"}), 404
    return jsonify(task)


@app.route("/api/tasks/<int:task_id>", methods=["PUT"])
def update_task(task_id):
    if not db.get_task(task_id):
        return jsonify({"error": "task not found"}), 404

    data = request.get_json(force=True, silent=True) or {}
    errors = validate_task_input(data)
    if errors:
        return jsonify({"error": "; ".join(errors)}), 400

    fields = {}
    if "title" in data:
        fields["title"] = data["title"].strip()
    if "description" in data:
        fields["description"] = data["description"].strip()
    if "priority" in data:
        fields["priority"] = data["priority"]
    if "status" in data:
        fields["status"] = data["status"]
    if "due_date" in data:
        fields["due_date"] = data["due_date"]

    task = db.update_task(task_id, **fields)
    return jsonify(task)


@app.route("/api/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    if not db.delete_task(task_id):
        return jsonify({"error": "task not found"}), 404
    return "", 204


if __name__ == "__main__":
    app.run(debug=True)
