import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "neovide" / "scripts"
FAKE_EDITOR = """#!{python}
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
tool = Path(sys.argv[0]).name
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([tool, args]) + "\\n")
ready = Path(os.environ["READY_FILE"])
if tool == "neovide":
    if os.environ.get("NEVER_READY") != "1":
        ready.write_text(str(os.getpid()))
    if os.environ.get("HOLD_LAUNCHER") == "1":
        import time
        time.sleep(30)
elif tool == "nvim":
    if "--remote-expr" in args and args[-1] == "1":
        sys.exit(0 if ready.exists() else 1)
    if "--remote" in args:
        sys.exit(int(os.environ.get("OPEN_EXIT", "0")))
"""


@unittest.skipIf(os.name == "nt", "POSIX command fixtures")
class NeovideTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="neovide-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.log = self.directory / "calls.jsonl"
        self.ready = self.directory / "ready"
        self.env = dict(os.environ, PATH=str(self.directory) + os.pathsep + os.environ["PATH"],
                        COPILOT_AGENT_SESSION_ID="test-session", CALL_LOG=str(self.log),
                        READY_FILE=str(self.ready), NO_COLOR="1")
        for name in ("nvim", "neovide", "sleep"):
            script = self.directory / name
            script.write_text(FAKE_EDITOR.format(python=sys.executable), encoding="utf-8")
            script.chmod(0o755)

    def runtimes(self):
        yield "shell", ["sh", str(SCRIPTS / "neovide-session.sh")]
        if shutil.which("pwsh"):
            yield "powershell", ["pwsh", "-NoProfile", "-File", str(SCRIPTS / "Neovide-Session.ps1")]

    def run_helper(self, command, *args, timeout=20):
        return subprocess.run(command + list(args), env=self.env, cwd=self.directory,
                              capture_output=True, text=True, timeout=timeout)

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def reset(self):
        self.log.unlink(missing_ok=True)
        self.ready.unlink(missing_ok=True)

    def test_launch_wait_and_open_literal_path_at_line(self):
        filename = "space ' quote | bracket [x].txt"
        for runtime, command in self.runtimes():
            with self.subTest(runtime=runtime):
                self.reset()
                result = self.run_helper(command, "open", filename, "42")
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.calls()
                launch = ["neovide", ["--fork", "--", "--listen", "/tmp/nvim-copilot-test-session"]]
                probe = ["nvim", ["--server", "/tmp/nvim-copilot-test-session", "--remote-expr", "1"]]
                self.assertEqual(calls[0], probe)
                self.assertEqual(calls.count(launch), 1)
                self.assertIn(probe, calls[calls.index(launch) + 1:])
                self.assertEqual(calls[-2:], [
                    ["nvim", ["--server", "/tmp/nvim-copilot-test-session", "--remote", str(self.directory / filename)]],
                    ["nvim", ["--server", "/tmp/nvim-copilot-test-session", "--remote-expr", "cursor(42, 1)"]],
                ])

    def test_existing_server_is_reused_and_open_failure_is_reported(self):
        for runtime, command in self.runtimes():
            for exit_code in ("0", "1"):
                with self.subTest(runtime=runtime, exit_code=exit_code):
                    self.reset()
                    self.ready.touch()
                    self.env["OPEN_EXIT"] = exit_code
                    result = self.run_helper(command, "open", str(self.directory / "file"))
                    self.assertEqual(result.returncode, int(exit_code), result.stderr)
                    self.assertEqual([call[0] for call in self.calls()], ["nvim", "nvim"])
                    if exit_code == "1":
                        self.assertNotIn("Opened in Neovide", result.stdout)
                        self.assertIn("File could not be opened", result.stderr)

    def test_invalid_line_or_missing_session_never_contacts_editor(self):
        for runtime, command in self.runtimes():
            for line in ("0", "-1", "x", "1 | quit"):
                with self.subTest(runtime=runtime, line=line):
                    self.reset()
                    result = self.run_helper(command, "open", "file", line)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.calls(), [])
            with self.subTest(runtime=runtime, session="missing"):
                self.reset()
                self.env["COPILOT_AGENT_SESSION_ID"] = ""
                result = self.run_helper(command, "open", "file")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])
                self.env["COPILOT_AGENT_SESSION_ID"] = "test-session"

    def test_readiness_timeout_does_not_open_file(self):
        command = ["sh", str(SCRIPTS / "neovide-session.sh")]
        self.env["NEVER_READY"] = "1"
        result = self.run_helper(command, "open", "file")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("within 10 seconds", result.stderr)
        self.assertEqual(sum(call[0] == "neovide" for call in self.calls()), 1)
        self.assertFalse(any("--remote" in args for _, args in self.calls()))

    def test_launcher_that_stays_running_does_not_block_open(self):
        self.env["HOLD_LAUNCHER"] = "1"
        command = ["sh", str(SCRIPTS / "neovide-session.sh")]
        try:
            result = self.run_helper(command, "open", "file", timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(any("--remote" in args for _, args in self.calls()))
        finally:
            if self.ready.exists():
                try:
                    os.kill(int(self.ready.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def test_close_only_contacts_existing_server_and_never_launches(self):
        for runtime, command in self.runtimes():
            for running in (False, True):
                with self.subTest(runtime=runtime, running=running):
                    self.reset()
                    if running:
                        self.ready.touch()
                    result = self.run_helper(command, "close")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse(any(tool == "neovide" for tool, _ in self.calls()))
                    sends = [args for _, args in self.calls() if "--remote-send" in args]
                    self.assertEqual(sends, [
                        ["--server", "/tmp/nvim-copilot-test-session", "--remote-send", r"<C-\><C-N>:qa!<CR>"]
                    ] if running else [])

    @unittest.skipUnless(shutil.which("nvim"), "Neovim not installed")
    def test_real_neovim_opens_literal_filename_at_requested_line_and_closes(self):
        session = "neovide-test-" + uuid.uuid4().hex
        server = "/tmp/nvim-copilot-" + session
        filename = self.directory / "space ' quote | bracket [x].txt"
        filename.write_text("example\n" * 50, encoding="utf-8")
        nvim = shutil.which("nvim")
        process = subprocess.Popen([nvim, "--headless", "--clean", "-n", "--listen", server],
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)

        def cleanup():
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)

        self.addCleanup(cleanup)
        env = dict(os.environ, COPILOT_AGENT_SESSION_ID=session)
        command = ["sh", str(SCRIPTS / "neovide-session.sh")]
        for _ in range(50):
            probe = subprocess.run([nvim, "--server", server, "--remote-expr", "1"],
                                   capture_output=True, timeout=5)
            if probe.returncode == 0:
                break
            time.sleep(0.1)
        else:
            self.fail("Headless Neovim did not become ready.")

        result = subprocess.run(command + ["open", str(filename), "042"],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(
            [nvim, "--server", server, "--remote-expr",
             """json_encode([expand('%:p'), line('.')])"""],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [str(filename), 42])
        result = subprocess.run(command + ["close"], env=env, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(process.wait(timeout=5), 0)


if __name__ == "__main__":
    unittest.main()
