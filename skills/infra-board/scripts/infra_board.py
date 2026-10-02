"""Shared infrastructure board for agents on this machine. Python 3 stdlib only."""

import argparse
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

TYPES = ("request", "grant", "deny", "claim", "release")
AGENTS = ("claude", "codex", "opencode", "copilot", "admin")
LIFETIMES = ("task", "demo", "persistent")
NOTE_MAX = 200

SCHEMA = f"""
CREATE TABLE IF NOT EXISTS entries (
    id        INTEGER PRIMARY KEY,
    at        TEXT NOT NULL,
    type      TEXT NOT NULL CHECK (type IN {TYPES}),
    agent     TEXT NOT NULL CHECK (agent IN {AGENTS}),
    thread    TEXT NOT NULL,
    resource  TEXT NOT NULL,
    lifetime  TEXT CHECK (lifetime IN {LIFETIMES}),
    container TEXT,
    ports     TEXT,
    ref       INTEGER REFERENCES entries (id),
    note      TEXT CHECK (length(note) <= {NOTE_MAX})
);
CREATE VIEW IF NOT EXISTS open_claims AS
    SELECT c.* FROM entries c
    WHERE c.type = 'claim' AND NOT EXISTS (
        SELECT 1 FROM entries r
        WHERE r.type = 'release' AND r.resource = c.resource AND r.thread = c.thread AND r.id > c.id);
CREATE VIEW IF NOT EXISTS open_requests AS
    SELECT q.* FROM entries q
    WHERE q.type = 'request' AND NOT EXISTS (
        SELECT 1 FROM entries a WHERE a.type IN ('grant', 'deny') AND a.ref = q.id);
"""

COLUMNS = ("id", "at", "agent", "thread", "resource", "lifetime", "container", "ports", "note")


def connect() -> sqlite3.Connection:
    db = sqlite3.connect(Path.home() / "infra-board.db")
    db.executescript(SCHEMA)
    return db


def show(title: str, rows: list) -> None:
    print(f"{title}: {len(rows)}")
    for row in rows:
        print("  " + "  ".join(f"{k}={v}" for k, v in zip(COLUMNS, row) if v is not None))


def cmd_list(args) -> None:
    db = connect()
    cols = ", ".join(COLUMNS)
    show("Open claims", db.execute(f"SELECT {cols} FROM open_claims ORDER BY id").fetchall())
    show("Open requests", db.execute(f"SELECT {cols} FROM open_requests ORDER BY id").fetchall())


def cmd_post(args) -> None:
    if args.type in ("request", "claim") and not args.lifetime:
        raise SystemExit(f"--lifetime is required for {args.type}")
    if args.type in ("grant", "deny") and args.ref is None:
        raise SystemExit(f"--ref is required for {args.type}")
    if args.note and len(args.note) > NOTE_MAX:
        raise SystemExit(f"--note is {len(args.note)} characters; the limit is {NOTE_MAX}")
    db = connect()
    with db:
        cur = db.execute(
            "INSERT INTO entries (at, type, agent, thread, resource, lifetime, container, ports, ref, note)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(timespec="seconds"), args.type, args.agent, args.thread,
             args.resource, args.lifetime, args.container, args.ports, args.ref, args.note))
    print(f"Posted entry {cur.lastrowid}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="Open claims and requests").set_defaults(func=cmd_list)
    post = sub.add_parser("post", help="Append one entry")
    post.add_argument("type", choices=TYPES)
    post.add_argument("--agent", required=True, choices=AGENTS)
    post.add_argument("--thread", required=True, help="T3 thread id, or - for cron and CI")
    post.add_argument("--resource", required=True, help="kebab name, e.g. mssql, bc-instance, devtunnel")
    post.add_argument("--lifetime", choices=LIFETIMES)
    post.add_argument("--container")
    post.add_argument("--ports")
    post.add_argument("--ref", type=int, help="id of the request a grant or deny answers")
    post.add_argument("--note")
    post.set_defaults(func=cmd_post)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
