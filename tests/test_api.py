import json


def post_task(client, **kwargs):
    data = {"title": "Test task", "priority": "medium"}
    data.update(kwargs)
    return client.post("/api/tasks", data=json.dumps(data), content_type="application/json")


def test_create_task(client):
    r = post_task(client, title="Buy milk", description="2%", priority="high", due_date="2026-06-15")
    assert r.status_code == 201
    task = r.get_json()
    assert task["title"] == "Buy milk"
    assert task["description"] == "2%"
    assert task["priority"] == "high"
    assert task["status"] == "open"
    assert task["due_date"] == "2026-06-15"
    assert task["id"] is not None


def test_list_tasks(client):
    post_task(client, title="A")
    post_task(client, title="B")
    r = client.get("/api/tasks")
    assert r.status_code == 200
    assert len(r.get_json()) == 2


def test_get_task(client):
    task_id = post_task(client).get_json()["id"]
    r = client.get(f"/api/tasks/{task_id}")
    assert r.status_code == 200
    assert r.get_json()["id"] == task_id


def test_get_task_not_found(client):
    r = client.get("/api/tasks/999")
    assert r.status_code == 404


def test_update_task(client):
    task_id = post_task(client).get_json()["id"]
    r = client.put(f"/api/tasks/{task_id}", data=json.dumps({"status": "done", "priority": "low"}), content_type="application/json")
    assert r.status_code == 200
    task = r.get_json()
    assert task["status"] == "done"
    assert task["priority"] == "low"


def test_update_task_not_found(client):
    r = client.put("/api/tasks/999", data=json.dumps({"status": "done"}), content_type="application/json")
    assert r.status_code == 404


def test_delete_task(client):
    task_id = post_task(client).get_json()["id"]
    r = client.delete(f"/api/tasks/{task_id}")
    assert r.status_code == 204
    r = client.get(f"/api/tasks/{task_id}")
    assert r.status_code == 404


def test_delete_task_not_found(client):
    r = client.delete("/api/tasks/999")
    assert r.status_code == 404


def test_create_missing_title(client):
    r = client.post("/api/tasks", data=json.dumps({}), content_type="application/json")
    assert r.status_code == 400
    assert "title" in r.get_json()["error"]


def test_create_empty_title(client):
    r = client.post("/api/tasks", data=json.dumps({"title": "   "}), content_type="application/json")
    assert r.status_code == 400


def test_create_invalid_priority(client):
    r = post_task(client, priority="urgent")
    assert r.status_code == 400
    assert "priority" in r.get_json()["error"]


def test_create_invalid_due_date(client):
    r = post_task(client, due_date="not-a-date")
    assert r.status_code == 400
    assert "due_date" in r.get_json()["error"]


def test_update_invalid_status(client):
    task_id = post_task(client).get_json()["id"]
    r = client.put(f"/api/tasks/{task_id}", data=json.dumps({"status": "archived"}), content_type="application/json")
    assert r.status_code == 400
