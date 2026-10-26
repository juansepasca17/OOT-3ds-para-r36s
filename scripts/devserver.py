#!/usr/bin/env python3
"""Job server for testing ports on the R36S without moving the SD card.

The console runs the "OOT3D Dev" agent, which polls this server, downloads the
current job and its files, runs it and uploads the results. Everything is plain
HTTP on the local network and every request must carry the shared token.

Layout of the served directory (default: work/devserver):
    token.txt        shared secret (also in oot3d/dev/agent.conf on the SD)
    job.txt          id of the current job (agent runs it once per id)
    job.sh           the job itself (bash, run on the console)
    files/<name>     files a job can fetch (binaries, libs, configs)
    results/<id>/    uploads from the console (job.log, json, ...)
    heartbeat.txt    last time the agent polled, its address and last job

Usage: python devserver.py [--root DIR] [--port 8765]
"""
import argparse
import hmac
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

SAFE_NAME = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")


def safe(name: str) -> bool:
    return bool(name) and set(name) <= SAFE_NAME and not name.startswith(".")


class Handler(BaseHTTPRequestHandler):
    root: Path
    token: str

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s %s\n" % (time.strftime("%H:%M:%S"), self.client_address[0], fmt % args))

    def authorized(self, query) -> bool:
        given = query.get("t", [""])[0]
        return hmac.compare_digest(given, self.token)

    def reply(self, code: int, body: bytes = b"", ctype: str = "text/plain") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if not self.authorized(query):
            return self.reply(403, b"forbidden\n")
        parts = [unquote(p) for p in url.path.strip("/").split("/") if p]
        if parts == ["ping"]:
            return self.reply(200, b"ok\n")
        if parts == ["heartbeat"]:
            last = query.get("last", ["-"])[0]
            note = "%s %s last_job=%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), self.client_address[0], last)
            (self.root / "heartbeat.txt").write_text(note)
            return self.reply(200, b"ok\n")
        if parts in (["job.txt"], ["job.sh"]):
            path = self.root / parts[0]
        elif len(parts) == 2 and parts[0] == "files" and safe(parts[1]):
            path = self.root / "files" / parts[1]
        else:
            return self.reply(404, b"not found\n")
        if not path.is_file():
            return self.reply(404, b"not found\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(path.stat().st_size))
        self.end_headers()
        with path.open("rb") as source:
            while chunk := source.read(1 << 20):
                self.wfile.write(chunk)

    def do_POST(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        if not self.authorized(query):
            return self.reply(403, b"forbidden\n")
        parts = [unquote(p) for p in url.path.strip("/").split("/") if p]
        if len(parts) != 3 or parts[0] != "upload" or not safe(parts[1]) or not safe(parts[2]):
            return self.reply(400, b"bad upload path\n")
        length = int(self.headers.get("Content-Length", "0"))
        if length > 256 * 1024 * 1024:
            return self.reply(413, b"too large\n")
        target = self.root / "results" / parts[1]
        target.mkdir(parents=True, exist_ok=True)
        with (target / parts[2]).open("wb") as sink:
            remaining = length
            while remaining > 0:
                chunk = self.rfile.read(min(remaining, 1 << 20))
                if not chunk:
                    break
                sink.write(chunk)
                remaining -= len(chunk)
        self.log_message("stored results/%s/%s (%d bytes)", parts[1], parts[2], length)
        return self.reply(200, b"stored\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent / "work" / "devserver")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    root = args.root.resolve()
    (root / "files").mkdir(parents=True, exist_ok=True)
    (root / "results").mkdir(exist_ok=True)
    token_file = root / "token.txt"
    if not token_file.is_file():
        token_file.write_text(os.urandom(16).hex() + "\n")
    Handler.root = root
    Handler.token = token_file.read_text().strip()
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("devserver on port %d, root %s" % (args.port, root), flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
