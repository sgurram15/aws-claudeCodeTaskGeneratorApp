import os
import tempfile

import pytest

from app import app
import db


@pytest.fixture
def client():
    fd, db_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    app.config["DATABASE"] = db_path
    app.config["TESTING"] = True
    db.init_db(app)

    with app.test_client() as c:
        yield c

    os.unlink(db_path)
