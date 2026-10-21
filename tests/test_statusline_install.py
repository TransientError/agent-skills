import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("bash") and shutil.which("node") and os.name == "posix",
                     "Requires Bash, Node, and POSIX symlinks")
class StatuslineInstallTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="statusline-install-")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.copilot = self.home / "custom copilot"
        relay = self.copilot / "extensions/agent-relay/bin/agent-relay-statusline.mjs"
        relay.parent.mkdir(parents=True)
        relay.touch()
        self.settings = self.copilot / "settings.json"
        self.target = self.home / ".config/copilot-statusline"
        self.env = dict(os.environ, HOME=str(self.home), COPILOT_HOME=str(self.copilot))

    def run_install(self, *args):
        return subprocess.run(["bash", str(ROOT / "install-statusline.sh"), *args],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def test_link_merge_backup_and_idempotency(self):
        original = '{"model":"keep","footer":{"showQuota":false}}'
        self.settings.write_text(original)
        self.target.mkdir(parents=True)
        (self.target / "settings.json").write_text('{"keep":true}')
        self.assertNotEqual(self.run_install().returncode, 0)
        result = self.run_install("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(self.target.resolve(), ROOT / "config/copilot-statusline")
        settings = json.loads(self.settings.read_text())
        self.assertEqual(settings["model"], "keep")
        self.assertEqual(settings["footer"], {"showQuota": False, "showCustom": True})
        self.assertIn("copilot-statusline@0.1.24", settings["statusLine"]["command"])
        backup = list(self.copilot.glob("settings.json.*.bak"))
        self.assertEqual(len(backup), 1)
        self.assertEqual(backup[0].read_text(), original)
        old_directory = list(self.target.parent.glob("copilot-statusline.*.bak"))
        self.assertEqual(len(old_directory), 1)
        self.assertEqual((old_directory[0] / "settings.json").read_text(), '{"keep":true}')
        self.assertEqual(self.run_install().returncode, 0)
        self.assertEqual(len(list(self.copilot.glob("settings.json.*.bak"))), 1)

    def test_dry_run_writes_nothing(self):
        result = self.run_install("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.target.exists())
        self.assertFalse(self.settings.exists())

    def test_invalid_json_prevents_link(self):
        self.settings.write_text("{invalid")
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.settings.read_text(), "{invalid")

    def test_missing_relay_prevents_link(self):
        self.env["COPILOT_HOME"] = str(self.home / "missing")
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Install Agent Relay first", result.stderr)
        self.assertFalse(self.target.exists())

    def test_broken_link_is_preserved_then_backed_up(self):
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(self.home / "missing")
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertTrue(self.target.is_symlink())
        result = self.run_install("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.resolve(), ROOT / "config/copilot-statusline")
        backups = list(self.target.parent.glob("copilot-statusline.*.bak"))
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].is_symlink())


if __name__ == "__main__":
    unittest.main()
