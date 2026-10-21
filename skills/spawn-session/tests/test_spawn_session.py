import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "scripts" / "spawn-session.sh"
FAKE_TERMINAL = r"""
import json
import os
from pathlib import Path
import socket
import sys

args = sys.argv[1:]
program = Path(sys.argv[0]).name
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([program, *args]) + "\n")
if program == "kitty":
    if os.environ.get("KITTY_FAIL"):
        sys.exit(1)
    address = args[args.index("--listen-on") + 1]
    path = address.removeprefix("unix:")
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(path)
    sock.close()
    if not os.environ.get("KITTY_NOT_READY"):
        Path(path + ".ready").touch()
elif program == "kitten":
    address = args[args.index("--to") + 1]
    if args[-1] == "ls":
        if not Path(address.removeprefix("unix:") + ".ready").exists():
            sys.exit(1)
        print(json.dumps([{"tabs": [{"windows": [{"id": 1}]}]}]))
        sys.exit(0)
    if "close-window" in args:
        sys.exit(1 if os.environ.get("KITTY_CLOSE_FAIL") else 0)
    if "launch" not in args:
        sys.exit(2)
    print(os.environ.get("KITTY_HANDLE", "42"))
"""


@unittest.skipUnless(os.name == "posix" and shutil.which("bash") and shutil.which("node"),
                     "Requires Bash, Node.js, and Unix sockets")
class SpawnSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.work = self.root / "work dir"
        self.work.mkdir()
        self.log = self.root / "calls.jsonl"
        home = self.root / "copilot"
        entry = home / "extensions" / "agent-relay" / "extension.mjs"
        entry.parent.mkdir(parents=True)
        entry.touch()
        for program in ("kitty", "kitten", "copilot"):
            target = self.bin / program
            target.write_text(f"#!{sys.executable}\n{FAKE_TERMINAL}", encoding="utf-8")
            target.chmod(0o755)
        sleep = self.bin / "sleep"
        sleep.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        sleep.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("KITTY_", "AGENT_RELAY_"))}
        self.env.update(
            PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            XDG_RUNTIME_DIR=str(self.runtime),
            COPILOT_HOME=str(home),
            CALL_LOG=str(self.log),
        )

    def listener(self, suffix, ready=True):
        path = self.runtime / f"spawn-session-kitty-{os.getuid()}-{suffix}.sock"
        with socket.socket(socket.AF_UNIX) as sock:
            sock.bind(str(path))
        if ready:
            Path(str(path) + ".ready").touch()
        return f"unix:{path}"

    def run_helper(self, *args):
        return subprocess.run(
            ["bash", str(HELPER), "--working-directory", str(self.work),
             "--name", "test-peer", *args],
            env=self.env, capture_output=True, text=True, timeout=15,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def result(self, *args):
        result = self.run_helper(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_reuses_responsive_socket_without_starting_kitty(self):
        address = self.listener("existing")
        result = self.result("--model", "model with spaces")
        self.assertEqual(result["kitty_address"], address)
        self.assertFalse(result["kitty_started"])
        self.assertEqual(result["kitty_start_command"], [])
        self.assertEqual(result["terminal_handle"], "42")
        self.assertEqual(result["command"][-2:], ["--model", "model with spaces"])
        self.assertEqual([call[0] for call in self.calls()], ["kitten", "kitten"])

    def test_starts_listener_then_reuses_it_on_next_launch(self):
        first = self.result()
        self.assertTrue(first["kitty_started"])
        self.assertEqual(first["focus"], "new-window-may-take-focus")
        self.assertIn("allow_remote_control=socket-only", first["kitty_start_command"])
        self.assertIn(f"spawn-session-kitty-{os.getuid()}-", first["kitty_address"])
        second = self.result()
        self.assertFalse(second["kitty_started"])
        self.assertEqual(first["kitty_address"], second["kitty_address"])
        self.assertNotEqual(first["session_id"], second["session_id"])
        self.assertEqual(sum(call[0] == "kitty" for call in self.calls()), 1)
        closes = [call for call in self.calls() if "close-window" in call]
        self.assertEqual(len(closes), 1)
        self.assertEqual(closes[0][-2:], ["--match", "id:1"])
        launch_index = next(i for i, call in enumerate(self.calls()) if "launch" in call)
        close_index = next(i for i, call in enumerate(self.calls()) if "close-window" in call)
        self.assertLess(launch_index, close_index)

    def test_skips_stale_socket(self):
        stale = self.listener("a-stale", ready=False)
        live = self.listener("b-live")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["kitty_address"], live)
        self.assertIn(stale.removeprefix("unix:"), result.stderr)

    def test_explicit_address_overrides_environment_and_discovery(self):
        explicit = self.listener("explicit")
        self.env["KITTY_LISTEN_ON"] = "unix:/unused"
        result = self.result("--kitty-address", explicit)
        self.assertEqual(result["kitty_address"], explicit)
        self.assertEqual(len(self.calls()), 1)

    def test_environment_address_overrides_discovery(self):
        self.env["KITTY_LISTEN_ON"] = "unix:/selected"
        self.assertEqual(self.result()["kitty_address"], "unix:/selected")
        self.assertEqual(len(self.calls()), 1)

    def test_dry_run_has_no_terminal_side_effects(self):
        result = self.result("--dry-run")
        self.assertEqual(result["status"], "planned")
        self.assertFalse(result["kitty_started"])
        self.assertEqual(result["kitty_start_command"][0], "kitty")
        self.assertFalse(self.log.exists())
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_failed_kitty_start_does_not_launch_peer(self):
        self.env["KITTY_FAIL"] = "1"
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not start", result.stderr)
        self.assertFalse(any("launch" in call for call in self.calls()))

    def test_listener_timeout_does_not_launch_peer(self):
        self.env["KITTY_NOT_READY"] = "1"
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("socket is not ready", result.stderr)
        self.assertEqual(sum(call[0] == "kitty" for call in self.calls()), 1)
        self.assertFalse(any("launch" in call for call in self.calls()))

    def test_invalid_launch_handle_is_reported(self):
        self.listener("existing")
        self.env["KITTY_HANDLE"] = "not-a-window-id"
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no valid window ID", result.stderr)

    def test_failed_launch_does_not_close_initial_window(self):
        self.env["KITTY_HANDLE"] = "not-a-window-id"
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("close-window" in call for call in self.calls()))

    def test_failed_initial_window_cleanup_reports_peer_already_launched(self):
        self.env["KITTY_CLOSE_FAIL"] = "1"
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Peer launched in window 42", result.stderr)
        self.assertIn("do not relaunch", result.stderr)

    def test_missing_relay_fails_before_starting_terminal(self):
        self.env["COPILOT_HOME"] = str(self.root / "missing")
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Agent Relay is not installed", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
