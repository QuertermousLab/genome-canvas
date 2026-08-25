"""Persistent password-free workspace names for Genome Canvas."""

import hashlib
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


class WorkspaceError(ValueError):
    pass


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def normalize_workspace_name(value):
    name = " ".join(str(value or "").split())
    if not name:
        raise WorkspaceError("Workspace name is required")
    if len(name) > 48:
        raise WorkspaceError("Workspace name must be 48 characters or fewer")
    if any(ord(character) < 32 or character in "/\\" for character in name):
        raise WorkspaceError("Workspace name contains unsupported characters")
    return name


def manual_workspace_id(name):
    digest = hashlib.sha256(name.casefold().encode("utf-8")).hexdigest()[:18]
    return "manual-{}".format(digest)


class WorkspaceStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()

    def connect(self):
        connection = sqlite3.connect(str(self.path), timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        return connection

    def initialize(self):
        with self.connect() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS workspaces (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS hidden_home_workspaces (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    hidden_at TEXT NOT NULL
                );
                """
            )
        try:
            self.path.chmod(0o600)
        except OSError:
            pass

    @staticmethod
    def public_workspace(row):
        return {
            "id": row["id"],
            "name": row["name"],
            "kind": "manual",
            "createdAt": row["created_at"],
        }

    def list_manual(self):
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT id, name, created_at FROM workspaces ORDER BY name COLLATE NOCASE"
            ).fetchall()
        return [self.public_workspace(row) for row in rows]

    def get_manual(self, workspace_id):
        with self.connect() as connection:
            row = connection.execute(
                "SELECT id, name, created_at FROM workspaces WHERE id = ?",
                (str(workspace_id or ""),),
            ).fetchone()
        return self.public_workspace(row) if row else None

    def create(self, value):
        name = normalize_workspace_name(value)
        workspace_id = manual_workspace_id(name)
        now = utc_now()
        try:
            with self.connect() as connection:
                connection.execute(
                    "INSERT INTO workspaces(id, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (workspace_id, name, now, now),
                )
        except sqlite3.IntegrityError:
            raise WorkspaceError("A manual workspace with that name already exists")
        return self.get_manual(workspace_id)

    def delete(self, workspace_id):
        with self.connect() as connection:
            result = connection.execute("DELETE FROM workspaces WHERE id = ?", (workspace_id,))
        if not result.rowcount:
            raise WorkspaceError("Manual workspace was not found")

    def hidden_homes(self):
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT id, name, hidden_at FROM hidden_home_workspaces ORDER BY name COLLATE NOCASE"
            ).fetchall()
        return [
            {"id": row["id"], "name": row["name"], "kind": "home", "hiddenAt": row["hidden_at"]}
            for row in rows
        ]

    def hide_home(self, workspace_id, name):
        with self.connect() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO hidden_home_workspaces(id, name, hidden_at) VALUES (?, ?, ?)",
                (workspace_id, name, utc_now()),
            )

    def restore_home(self, workspace_id):
        with self.connect() as connection:
            result = connection.execute("DELETE FROM hidden_home_workspaces WHERE id = ?", (workspace_id,))
        if not result.rowcount:
            raise WorkspaceError("Hidden Home workspace was not found")
