"""Pytest fixtures per SOLEM backend.

Test isolato: usa SQLite in-memory (no scrittura disco), risetta DB tra test.
"""
import os
import sys
from pathlib import Path

import pytest

# Forza path al backend
sys.path.insert(0, str(Path(__file__).parent.parent))

# Forza SQLite in-memory PRIMA di importare layers.db
os.environ["SOLEM_DB_PATH"] = ":memory:"


@pytest.fixture(autouse=True)
def reset_db():
    """Reset DB singleton tra ogni test."""
    from solem_api.layers import db
    db.close()
    yield
    db.close()


@pytest.fixture
def client():
    """TestClient FastAPI configurato sull'app SOLEM."""
    from fastapi.testclient import TestClient
    from solem_api.main import app
    return TestClient(app)
