"""Deterministic helpers for the take-over skill. Python 3 stdlib only."""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_LABEL = "take-over"
TOKEN_TTL_SECONDS = 15 * 60
TOKEN_REUSE_MARGIN = 14 * 60


def t3_home() -> Path:
    home = os.environ.get("T3CODE_HOME")
    return Path(home) if home else Path.home() / ".t3"


def load_runtime() -> dict:
    data = json.loads((t3_home() / "userdata" / "server-runtime.json").read_text())
    return {"origin": data["origin"].rstrip("/")}


def environment_id() -> str:
    return (t3_home() / "userdata" / "environment-id").read_text().strip()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def token_file_path() -> Path:
    return Path(tempfile.gettempdir()) / "t3-takeover.tok"


def mint_token(label: str) -> str:
    out = subprocess.run(
        ["t3", "auth", "session", "issue", "--label", label, "--ttl", "15m", "--token-only"],
        capture_output=True, text=True, check=True,
    )
    token = out.stdout.strip()
    if not token:
        print("token minting produced no output", file=sys.stderr)
        sys.exit(1)
    return token


def get_token(args) -> str:
    if args.token:
        return args.token
    path = Path(args.token_file)
    if path.is_file() and time.time() - path.stat().st_mtime < TOKEN_REUSE_MARGIN:
        token = path.read_text().strip()
        if token:
            return token
    token = mint_token(args.label)
    Path(args.token_file).write_text(token)
    return token


def api_request(method: str, url: str, token: str, payload: dict | None = None) -> dict:
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode()
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} for {method} {url}\n{e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    return json.loads(text) if text else {}


def dispatch(args, command: dict) -> dict:
    runtime = load_runtime()
    return api_request("POST", runtime["origin"] + "/api/orchestration/dispatch",
                       get_token(args), command)


def snapshot(args, thread_id: str) -> dict:
    runtime = load_runtime()
    return api_request("GET", runtime["origin"] + "/api/orchestration/threads/" + thread_id,
                       get_token(args))


def build_link(args, thread_id: str) -> str:
    return f"{load_runtime()['origin']}/{environment_id()}/{thread_id}"


def model_selection_from(snapshot_thread: dict) -> dict:
    ms = snapshot_thread.get("modelSelection") or {}
    out = {}
    if ms.get("instanceId"):
        out["instanceId"] = ms["instanceId"]
    elif ms.get("provider"):
        out["instanceId"] = ms["provider"]
    out["model"] = ms["model"]
    if ms.get("options") is not None:
        out["options"] = ms["options"]
    return out


def cmd_link(args) -> None:
    print(build_link(args, args.thread_id))


def cmd_snapshot(args) -> None:
    snap = snapshot(args, args.thread_id)
    if args.raw:
        print(json.dumps(snap, indent=2))
        return
    t = snap["thread"]
    msgs = t.get("messages", [])
    last_user = next((m for m in reversed(msgs) if m.get("role") == "user"), None)
    notes = [m["text"] for m in msgs
             if m.get("role") == "user" and m.get("text", "").startswith("[take-over")]
    print(json.dumps({
        "threadId": t["id"],
        "title": t["title"],
        "projectId": t["projectId"],
        "branch": t.get("branch"),
        "latestTurnState": (t.get("latestTurn") or {}).get("state"),
        "modelSelection": t.get("modelSelection"),
        "settledOverride": t.get("settledOverride"),
        "settledAt": t.get("settledAt"),
        "archivedAt": t.get("archivedAt"),
        "deletedAt": t.get("deletedAt"),
        "sessionStatus": (t.get("session") or {}).get("status"),
        "messageCount": len(msgs),
        "lastUserMessage": last_user["text"] if last_user else None,
        "takeOverNotes": notes,
        "link": build_link(args, t["id"]),
    }, indent=2))


def cmd_claim(args) -> None:
    text = (f"[take-over] Thread {args.current} has taken over: {args.task}. "
            f"Source turn was {args.state} ({args.reason}). "
            f"Work continues in the taking-over thread; no reply needed here. "
            f"Original thread: {build_link(args, args.source)}")
    cmd = {
        "type": "thread.turn.start",
        "commandId": str(uuid.uuid4()),
        "threadId": args.source,
        "message": {"messageId": str(uuid.uuid4()), "role": "user",
                    "text": text, "attachments": []},
        "runtimeMode": "full-access",
        "interactionMode": "default",
        "createdAt": now_iso(),
    }
    result = dispatch(args, cmd)
    print(json.dumps({"dispatched": "claim", "sequence": result.get("sequence"), "text": text}))


def cmd_complete(args) -> None:
    parts = [f"[take-over] Thread {args.current} finished: {args.summary}"]
    if args.task:
        parts.append(f"Original task: {args.task}.")
    parts.append(f"Taking-over thread: {build_link(args, args.current)}")
    text = " ".join(parts)
    cmd = {
        "type": "thread.turn.start",
        "commandId": str(uuid.uuid4()),
        "threadId": args.source,
        "message": {"messageId": str(uuid.uuid4()), "role": "user",
                    "text": text, "attachments": []},
        "runtimeMode": "full-access",
        "interactionMode": "default",
        "createdAt": now_iso(),
    }
    result = dispatch(args, cmd)
    print(json.dumps({"dispatched": "complete", "sequence": result.get("sequence"), "text": text}))


def cmd_title(args) -> None:
    cmd = {
        "type": "thread.meta.update",
        "commandId": str(uuid.uuid4()),
        "threadId": args.thread_id,
        "title": args.title,
    }
    result = dispatch(args, cmd)
    print(json.dumps({"dispatched": "title", "sequence": result.get("sequence"),
                      "threadId": args.thread_id, "title": args.title}))


def cmd_settle(args) -> None:
    cmd = {"type": "thread.settle", "commandId": str(uuid.uuid4()), "threadId": args.thread_id}
    result = dispatch(args, cmd)
    print(json.dumps({"dispatched": "settle", "sequence": result.get("sequence"),
                      "threadId": args.thread_id}))


def cmd_wake(args) -> None:
    snap = snapshot(args, args.source)
    thread = snap["thread"]
    text = (f"[take-over complete] Thread {args.current} finished: {args.done}. "
            f"Summary of what happened while you were stalled: {args.context}. "
            f"Acknowledge and continue here. "
            f"Taking-over thread: {build_link(args, args.current)}")
    cmd = {
        "type": "thread.turn.start",
        "commandId": str(uuid.uuid4()),
        "threadId": args.source,
        "message": {"messageId": str(uuid.uuid4()), "role": "user",
                    "text": text, "attachments": []},
        "modelSelection": model_selection_from(thread),
        "runtimeMode": thread.get("runtimeMode", "full-access"),
        "interactionMode": thread.get("interactionMode", "default"),
        "createdAt": now_iso(),
    }
    result = dispatch(args, cmd)
    out = {"dispatched": "wake", "sequence": result.get("sequence"), "text": text}
    if args.wait > 0:
        deadline = time.time() + args.wait
        state = None
        while time.time() < deadline:
            time.sleep(2)
            t = snapshot(args, args.source)["thread"]
            state = (t.get("latestTurn") or {}).get("state")
            if state and state != "queued":
                break
        out["turnState"] = state
        out["settledOverride"] = snapshot(args, args.source)["thread"].get("settledOverride")
    print(json.dumps(out))


def cmd_retire(args) -> None:
    cmd_type = "thread.delete" if args.hard else "thread.archive"
    cmd = {"type": cmd_type, "commandId": str(uuid.uuid4()), "threadId": args.thread_id}
    result = dispatch(args, cmd)
    print(json.dumps({"dispatched": cmd_type, "sequence": result.get("sequence"),
                      "threadId": args.thread_id}))


def cmd_status(args) -> None:
    t = snapshot(args, args.thread_id)["thread"]
    msgs = t.get("messages", [])
    claim = any(m.get("role") == "user" and "has taken over" in m.get("text", "")
                for m in msgs)
    completed = any(m.get("role") == "user" and "[take-over complete]" in m.get("text", "")
                    for m in msgs)
    turn = t.get("latestTurn") or {}
    report = {
        "threadId": t["id"],
        "title": t["title"],
        "latestTurnState": turn.get("state"),
        "settledOverride": t.get("settledOverride"),
        "settledAt": t.get("settledAt"),
        "archivedAt": t.get("archivedAt"),
        "deletedAt": t.get("deletedAt"),
        "claimNotePresent": claim,
        "completionNotePresent": completed,
        "link": build_link(args, t["id"]),
    }
    print(json.dumps(report, indent=2))
    ok = claim and not t.get("deletedAt")
    sys.exit(0 if ok else 1)


def cmd_cleanup(args) -> None:
    out = subprocess.run(["t3", "auth", "session", "list", "--json"],
                         capture_output=True, text=True, check=True)
    sessions = json.loads(out.stdout or "[]")
    revoked = []
    for s in sessions:
        if (s.get("client") or {}).get("label") == args.label:
            subprocess.run(["t3", "auth", "session", "revoke", s["sessionId"]],
                           capture_output=True, text=True, check=True)
            revoked.append(s["sessionId"])
    path = Path(args.token_file)
    removed = path.is_file()
    if removed:
        path.unlink()
    print(json.dumps({"revoked": revoked, "tokenFileRemoved": removed}))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--token", help="bearer token; overrides token file and minting")
    parser.add_argument("--token-file", default=str(token_file_path()))
    parser.add_argument("--label", default=DEFAULT_LABEL,
                        help="label used when minting and during cleanup")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("snapshot", help="read a thread snapshot (key fields)")
    p.add_argument("thread_id")
    p.add_argument("--raw", action="store_true", help="print the full API response")
    p.set_defaults(func=cmd_snapshot)

    p = sub.add_parser("link", help="print the UI link for a thread")
    p.add_argument("thread_id")
    p.set_defaults(func=cmd_link)

    p = sub.add_parser("claim", help="post the [take-over] claim note to the source thread")
    p.add_argument("--source", required=True)
    p.add_argument("--current", required=True)
    p.add_argument("--task", required=True, help="one-line task description")
    p.add_argument("--state", required=True, help="state of the stalled turn")
    p.add_argument("--reason", required=True, help="why the source thread stalled")
    p.set_defaults(func=cmd_claim)

    p = sub.add_parser("complete", help="post the [take-over] completion note to the source thread")
    p.add_argument("--source", required=True)
    p.add_argument("--current", required=True)
    p.add_argument("--summary", required=True, help="what was done and how it was verified")
    p.add_argument("--task", help="one-line original task")
    p.set_defaults(func=cmd_complete)

    p = sub.add_parser("title", help="set a thread title")
    p.add_argument("thread_id")
    p.add_argument("title")
    p.set_defaults(func=cmd_title)

    p = sub.add_parser("settle", help="settle a thread")
    p.add_argument("thread_id")
    p.set_defaults(func=cmd_settle)

    p = sub.add_parser("wake", help="resume the source thread with a completion turn (same driver)")
    p.add_argument("--source", required=True)
    p.add_argument("--current", required=True)
    p.add_argument("--done", required=True, help="what was finished and how it was verified")
    p.add_argument("--context", required=True, help="summary of what happened while stalled")
    p.add_argument("--wait", type=int, default=0, help="seconds to poll for turn state")
    p.set_defaults(func=cmd_wake)

    p = sub.add_parser("retire", help="archive (or delete) the taking-over thread")
    p.add_argument("thread_id")
    p.add_argument("--hard", action="store_true", help="delete instead of archive")
    p.set_defaults(func=cmd_retire)

    p = sub.add_parser("status", help="read-only take-over state report for a thread")
    p.add_argument("thread_id")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("cleanup", help="revoke sessions minted for this procedure and remove the token file")
    p.set_defaults(func=cmd_cleanup)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
