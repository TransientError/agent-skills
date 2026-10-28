import base64
from html import unescape
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "copy-rich-text" / "scripts"
RUNTIMES = [
    runtime for runtime in ("powershell.exe", "pwsh")
    if shutil.which(runtime)
]


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(RUNTIMES, "PowerShell is required")
class RichTextTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="rich-text-test-")
        self.addCleanup(temporary.cleanup)
        self.input = Path(temporary.name) / "message's input.json"

    def write_input(self, document):
        self.input.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")

    def run_ps(self, runtime, command):
        prelude = (
            "$ErrorActionPreference = 'Stop'; "
            "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); "
        )
        encoded = base64.b64encode((prelude + command).encode("utf-16-le")).decode()
        return subprocess.run(
            [runtime, "-NoProfile", "-STA", "-OutputFormat", "Text", "-EncodedCommand", encoded],
            capture_output=True, encoding="utf-8", timeout=30,
            env=dict(os.environ, NO_COLOR="1"),
        )

    def render(self, runtime, document):
        self.write_input(document)
        result = self.run_ps(
            runtime,
            f". {literal(SCRIPTS / 'RichText.ps1')}; "
            f"$doc = Get-Content -LiteralPath {literal(self.input)} -Raw -Encoding UTF8 "
            "| ConvertFrom-Json; "
            "ConvertTo-RichTextPayload -Document $doc | ConvertTo-Json -Compress",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_utf8_offsets_escape_markup_and_preserve_plain_text(self):
        text = 'Caf\u00e9 \u6f22\u5b57 \U0001f680 <script>& "quoted"'
        document = {"paragraphs": [
            [{"text": "Status: ", "bold": True}, {"text": text}],
            [{"text": "  example <file>\nnext\tline", "bold": True, "code": True}],
        ]}
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                payload = self.render(runtime, document)
                self.assertEqual(
                    payload["Text"],
                    "Status: " + text + "\r\n\r\n  example <file>\r\nnext\tline",
                )
                data = payload["Html"].encode("utf-8")
                self.assertGreater(len(data), len(payload["Html"]))
                offsets = {
                    name: int(value) for name, value in re.findall(
                        rb"(StartHTML|EndHTML|StartFragment|EndFragment):(\d{10})",
                        data,
                    )
                }
                self.assertEqual(len(offsets), 4)
                start = offsets[b"StartHTML"]
                end = offsets[b"EndHTML"]
                fragment_start = offsets[b"StartFragment"]
                fragment_end = offsets[b"EndFragment"]
                self.assertTrue(data[:start].endswith(b"\r\n"))
                self.assertEqual(end, len(data))
                self.assertEqual(data[start:fragment_start], b"<html><body><!--StartFragment-->")
                self.assertEqual(data[fragment_end:end], b"<!--EndFragment--></body></html>")
                fragment = data[fragment_start:fragment_end].decode("utf-8")
                self.assertIn("<b>Status: </b>", fragment)
                self.assertIn("&lt;script&gt;&amp; &quot;quoted&quot;", fragment)
                self.assertNotIn("<script>", fragment)
                self.assertIn("<b><code ", fragment)
                self.assertIn("  example &lt;file&gt;<br>next\tline</code></b>", fragment)
                self.assertIn(text, unescape(fragment))

    def test_single_run_empty_paragraph_and_line_endings(self):
        document = {"paragraphs": [
            [{"text": "literal `code` **stars**\rfirst\r\nsecond\nthird"}],
            [{"text": ""}],
        ]}
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                payload = self.render(runtime, document)
                self.assertEqual(
                    payload["Text"],
                    "literal `code` **stars**\r\nfirst\r\nsecond\r\nthird\r\n\r\n",
                )
                self.assertIn("literal `code` **stars**<br>first<br>second<br>third", payload["Html"])
                self.assertNotIn("<code ", payload["Html"])

    def test_dry_run_never_loads_clipboard_api_or_exposes_message(self):
        self.write_input({"paragraphs": [[{"text": "private sample \u6f22\u5b57"}]]})
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = self.run_ps(
                    runtime,
                    "function Add-Type { throw 'Clipboard API must not be loaded'; }; "
                    f"& {literal(SCRIPTS / 'Copy-RichText.ps1')} "
                    f"-InputPath {literal(self.input)} -DryRun",
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("private sample", result.stdout + result.stderr)
                status = json.loads(result.stdout)
                self.assertEqual(status["status"], "planned")
                self.assertGreater(status["htmlBytes"], 100)

    def test_invalid_shapes_and_flags_fail_before_clipboard_access(self):
        invalid = [
            {}, {"paragraphs": []}, {"paragraphs": ["text"]},
            {"paragraphs": [[]]}, {"paragraphs": [[{"text": 42}]]},
            {"paragraphs": [[{"text": "sample", "bold": "true"}]]},
            {"paragraphs": [[{"text": "sample", "code": None}]]},
            {"paragraphs": [[{"text": "sample", "html": "<b>raw</b>"}]]},
            {"paragraphs": [[{"text": "truncated\u0000text"}]]},
            {"paragraphs": [[{"text": "sample"}]], "extra": True},
        ]
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                self.write_input(invalid)
                result = self.run_ps(
                    runtime,
                    f". {literal(SCRIPTS / 'RichText.ps1')}; "
                    f"$docs = Get-Content -LiteralPath {literal(self.input)} -Raw -Encoding UTF8 "
                    "| ConvertFrom-Json; "
                    "$rejected = 0; foreach ($doc in $docs) { "
                    "try { $null = ConvertTo-RichTextPayload -Document $doc } "
                    "catch { $rejected++ } }; $rejected",
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(int(result.stdout), len(invalid))

    def test_bad_json_is_reported_without_echoing_content(self):
        self.input.write_text('{"private_message": oops}', encoding="utf-8")
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = self.run_ps(
                    runtime,
                    f"& {literal(SCRIPTS / 'Copy-RichText.ps1')} "
                    f"-InputPath {literal(self.input)} -DryRun",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot read input as UTF-8", result.stderr)
                self.assertIn("Check the file and JSON syntax.", result.stderr)
                self.assertNotIn("private_message", result.stdout + result.stderr)

    @unittest.skipUnless(os.name == "nt", "Windows PowerShell STA relaunch is Windows-only")
    def test_mta_relaunch_handles_quoted_unicode_paths_without_writing(self):
        self.write_input({"paragraphs": [[{"text": "dry run only"}]]})
        scripts = self.input.parent / "skill's \u6f22\u5b57 & space"
        shutil.copytree(SCRIPTS, scripts)
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = subprocess.run(
                    [runtime, "-NoProfile", "-MTA", "-File", str(scripts / "Copy-RichText.ps1"),
                     "-InputPath", str(self.input), "-DryRun"],
                    capture_output=True, encoding="utf-8", timeout=30,
                    env=dict(os.environ, NO_COLOR="1"),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"], "planned")

    @unittest.skipUnless(os.name == "nt", "WinForms writer is Windows-only")
    def test_writer_sets_both_formats_persistently_and_surfaces_failures(self):
        # Fake WinForms types prevent all access to the shared system clipboard.
        stub = r"""
Add-Type -TypeDefinition @'
namespace System.Windows.Forms {
    public static class DataFormats {
        public const string Html = "HTML Format";
        public const string UnicodeText = "UnicodeText";
    }
    public class DataObject {
        public System.Collections.Generic.Dictionary<string, object> Values =
            new System.Collections.Generic.Dictionary<string, object>();
        public void SetData(string format, object value) { Values.Add(format, value); }
    }
    public static class Clipboard {
        public static DataObject Data;
        public static bool Persistent;
        public static bool FailWrite;
        public static bool MissingFormat;
        public static void SetDataObject(object data, bool copy) {
            if (FailWrite) throw new System.InvalidOperationException("clipboard locked");
            Data = (DataObject)data; Persistent = copy;
        }
        public static bool ContainsData(string format) {
            return !MissingFormat && Data.Values.ContainsKey(format);
        }
    }
}
'@
function Add-Type { param($AssemblyName) }
"""
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                result = self.run_ps(
                    runtime,
                    stub + f"\n. {literal(SCRIPTS / 'RichText.ps1')}; " + r"""
$payload = [pscustomobject]@{ Html = 'rendered'; Text = 'fallback' }
Set-RichTextClipboard -Payload $payload
$data = [System.Windows.Forms.Clipboard]::Data.Values
if ($data['HTML Format'] -cne 'rendered' -or $data['UnicodeText'] -cne 'fallback' -or
    -not [System.Windows.Forms.Clipboard]::Persistent -or $data.Count -ne 2) {
    throw 'Wrong clipboard data or persistence'
}
[System.Windows.Forms.Clipboard]::FailWrite = $true
$failed = $false
try { Set-RichTextClipboard -Payload $payload } catch { $failed = $true }
if (-not $failed) { throw 'Clipboard lock was silently ignored' }
[System.Windows.Forms.Clipboard]::FailWrite = $false
[System.Windows.Forms.Clipboard]::MissingFormat = $true
$failed = $false
try { Set-RichTextClipboard -Payload $payload } catch { $failed = $true }
if (-not $failed) { throw 'Missing HTML format was silently ignored' }
'passed'
""",
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "passed")


if __name__ == "__main__":
    unittest.main()
