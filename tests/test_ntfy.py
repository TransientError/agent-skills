import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "ntfy" / "scripts"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.requests.append({"path": self.path, "payload": payload})
        mode = self.server.mode
        status = 500 if mode == "error" else 302 if mode == "redirect" else 200
        result = {"id": "message123", "event": "message", "topic": payload["topic"]}
        if mode == "wrong-topic":
            result["topic"] = "unexpected-topic"
        if mode == "error":
            result = {"error": "Do not echo this body: " + payload["topic"]}
        body = b"not JSON" if mode == "invalid-json" else json.dumps(result).encode("utf-8")
        self.send_response(status)
        if mode == "redirect":
            self.send_header("Location", "/redirect-target")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.server.requests.append({"path": self.path, "payload": None})
        self.send_error(500)


class NtfyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ntfy-test-")
        self.addCleanup(temporary.cleanup)
        self.topic_file = Path(temporary.name) / "topic.local.txt"
        self.topic = "test-private-topic"
        self.topic_file.write_text(self.topic + "\n", encoding="utf-8")
        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.server.requests = []
        self.server.mode = "success"
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}/"

    def commands(self):
        yield "python", [sys.executable, str(SCRIPTS / "send_ntfy.py")]
        if shutil.which("pwsh"):
            yield "powershell", ["pwsh", "-NoProfile", "-File", str(SCRIPTS / "Send-Ntfy.ps1")]

    def run_sender(self, runtime, command, *, dry_run=False, message="Finished.\nReady \u2713"):
        if runtime == "powershell":
            args = ["-Message", message, "-Title", "Test \u2713", "-Priority", "4",
                    "-TopicFile", str(self.topic_file), "-Server", self.url]
            if dry_run:
                args.append("-DryRun")
        else:
            args = ["--message", message, "--title", "Test \u2713", "--priority", "4",
                    "--topic-file", str(self.topic_file), "--server", self.url]
            if dry_run:
                args.append("--dry-run")
        result = subprocess.run(command + args, capture_output=True, encoding="utf-8",
                                timeout=25, env=dict(os.environ, NO_COLOR="1"))
        self.assertNotIn(self.topic, result.stdout + result.stderr)
        return result

    def test_dry_run_does_not_contact_server_or_expose_topic(self):
        for runtime, command in self.commands():
            with self.subTest(runtime=runtime):
                result = self.run_sender(runtime, command, dry_run=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"status": "planned"})
                self.assertEqual(self.server.requests, [])

    def test_utf8_json_is_published_to_root_with_redacted_result(self):
        for runtime, command in self.commands():
            with self.subTest(runtime=runtime):
                self.server.requests.clear()
                result = self.run_sender(runtime, command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"status": "published"})
                self.assertEqual(self.server.requests, [{
                    "path": "/", "payload": {
                        "topic": self.topic, "message": "Finished.\nReady \u2713",
                        "title": "Test \u2713", "priority": 4,
                    },
                }])

    def test_http_failure_is_not_retried_and_does_not_echo_server_body(self):
        self.server.mode = "error"
        for runtime, command in self.commands():
            with self.subTest(runtime=runtime):
                self.server.requests.clear()
                result = self.run_sender(runtime, command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unconfirmed", result.stderr)
                self.assertEqual(len(self.server.requests), 1)

    def test_redirects_and_invalid_confirmations_fail_without_retry(self):
        for mode in ["redirect", "invalid-json", "wrong-topic"]:
            self.server.mode = mode
            for runtime, command in self.commands():
                with self.subTest(mode=mode, runtime=runtime):
                    self.server.requests.clear()
                    result = self.run_sender(runtime, command)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("unconfirmed", result.stderr)
                    self.assertEqual(len(self.server.requests), 1)

    def test_missing_invalid_and_placeholder_topics_do_not_publish(self):
        for topic in [None, "", "two\nlines", "ntfy-topic-name"]:
            if topic is None:
                self.topic_file.unlink()
            else:
                self.topic_file.write_text(topic, encoding="utf-8")
            for runtime, command in self.commands():
                with self.subTest(topic=topic, runtime=runtime):
                    result = self.run_sender(runtime, command)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.server.requests, [])

    def test_oversized_payload_does_not_publish(self):
        for runtime, command in self.commands():
            with self.subTest(runtime=runtime):
                result = self.run_sender(runtime, command, message="x" * 5000)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.server.requests, [])


if __name__ == "__main__":
    unittest.main()
