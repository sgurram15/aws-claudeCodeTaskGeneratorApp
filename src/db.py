import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

_table = None


def _get_table():
    global _table
    if _table is None:
        dynamodb = boto3.resource("dynamodb")
        _table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
    return _table


def init_db(app):
    pass


def init_app(app):
    pass


def close_db(e=None):
    pass


def _item_to_task(item):
    return {
        "id": item["id"],
        "title": item["title"],
        "description": item.get("description", ""),
        "priority": item.get("priority", "medium"),
        "status": item.get("status", "open"),
        "due_date": item.get("due_date"),
        "created_at": item.get("created_at", ""),
    }


def list_tasks():
    table = _get_table()
    response = table.scan()
    items = response.get("Items", [])
    tasks = [_item_to_task(item) for item in items]
    tasks.sort(key=lambda t: t["created_at"], reverse=True)
    return tasks


def get_task(task_id):
    table = _get_table()
    response = table.get_item(Key={"id": str(task_id)})
    item = response.get("Item")
    if not item:
        return None
    return _item_to_task(item)


def create_task(title, description, priority, due_date):
    table = _get_table()
    task_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    item = {
        "id": task_id,
        "title": title,
        "description": description or "",
        "priority": priority,
        "status": "open",
        "created_at": now,
    }
    if due_date:
        item["due_date"] = due_date
    table.put_item(Item=item)
    return _item_to_task(item)


def update_task(task_id, **fields):
    task_id = str(task_id)
    if not get_task(task_id):
        return None
    allowed = {"title", "description", "priority", "status", "due_date"}
    fields = {k: v for k, v in fields.items() if k in allowed}
    if not fields:
        return get_task(task_id)
    table = _get_table()
    update_expr = "SET " + ", ".join(f"#{k} = :{k}" for k in fields)
    expr_names = {f"#{k}": k for k in fields}
    expr_values = {f":{k}": v for k, v in fields.items()}
    table.update_item(
        Key={"id": task_id},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )
    return get_task(task_id)


def delete_task(task_id):
    task_id = str(task_id)
    if not get_task(task_id):
        return False
    table = _get_table()
    table.delete_item(Key={"id": task_id})
    return True
