#!/usr/bin/env python3
"""Publish one ntfy message without exposing the private topic."""

import argparse
from http.client import HTTPException
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


def publish(args):
    try:
        topic = Path(args.topic_file).read_text(encoding="utf-8-sig").strip()
    except (OSError, UnicodeError):
        raise ValueError("Cannot read the private topic file; create topic.local.txt beside the skill.") from None
    if not re.fullmatch(r"[-_A-Za-z0-9]{1,64}", topic) or topic == "ntfy-topic-name":
        raise ValueError("The private topic file must contain one valid non-placeholder topic.")
    if not args.message.strip():
        raise ValueError("Message must not be blank.")

    server = urlsplit(args.server)
    if (not server.hostname or server.username is not None or server.password is not None
            or server.path not in ("", "/") or server.query or server.fragment
            or not (server.scheme == "https" or (server.scheme == "http"
                    and server.hostname in ("localhost", "127.0.0.1", "::1")))):
        raise ValueError("Server must be an HTTPS root URL, or HTTP loopback for local tests.")
    _ = server.port
    url = urlunsplit((server.scheme, server.netloc, "/", "", ""))
    data = json.dumps({"topic": topic, "message": args.message, "title": args.title,
                       "priority": args.priority}, ensure_ascii=False).encode("utf-8")
    if len(data) > 4096:
        raise ValueError("Notification payload must not exceed 4096 UTF-8 bytes.")
    if args.dry_run:
        return {"status": "planned"}

    request = Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with build_opener(NoRedirect()).open(request, timeout=15) as response:
            content = response.read(65537)
    except HTTPError as error:
        raise RuntimeError(f"Notification request failed (HTTP {error.code}); delivery is unconfirmed. Do not retry automatically.") from None
    except (URLError, OSError, TimeoutError, HTTPException):
        raise RuntimeError("Notification request failed; delivery is unconfirmed. Do not retry automatically.") from None
    try:
        if len(content) > 65536:
            raise ValueError("Response too large")
        result = json.loads(content)
    except (ValueError, UnicodeError):
        raise RuntimeError("Invalid server response; delivery is unconfirmed. Do not retry automatically.") from None
    if (not isinstance(result, dict) or result.get("event") != "message"
            or result.get("topic") != topic or not isinstance(result.get("id"), str)
            or not re.fullmatch(r"[-_A-Za-z0-9]+", result["id"])):
        raise RuntimeError("Server did not confirm publication; delivery is unconfirmed. Do not retry automatically.")
    return {"status": "published"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--message", required=True)
    parser.add_argument("--title", default="Agent notification")
    parser.add_argument("--priority", type=int, choices=range(1, 6), default=3)
    parser.add_argument("--topic-file", default=Path(__file__).resolve().parents[1] / "topic.local.txt")
    parser.add_argument("--server", default="https://ntfy.sh")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(publish(args)))
        return 0
    except (ValueError, RuntimeError) as error:
        print(f"ntfy: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
