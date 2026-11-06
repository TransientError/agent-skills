import base64
from collections import Counter
from html import unescape
from html.parser import HTMLParser
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


class Markup(HTMLParser):
    def __init__(self, fragment):
        super().__init__()
        self.starts = Counter()
        self.ends = Counter()
        self.attributes = {}
        self.feed(fragment)

    def handle_starttag(self, tag, attrs):
        self.starts[tag] += 1
        self.attributes.setdefault(tag, []).append(dict(attrs))

    def handle_endtag(self, tag):
        self.ends[tag] += 1


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

    def fragment(self, payload):
        data = payload["Html"].encode("utf-8")
        offsets = {
            name: int(value) for name, value in re.findall(
                rb"(StartHTML|EndHTML|StartFragment|EndFragment):(\d{10})", data
            )
        }
        self.assertEqual(len(offsets), 4)
        self.assertEqual(offsets[b"EndHTML"], len(data))
        self.assertEqual(
            data[offsets[b"StartHTML"]:offsets[b"StartFragment"]],
            b"<html><body><!--StartFragment-->",
        )
        self.assertEqual(
            data[offsets[b"EndFragment"]:offsets[b"EndHTML"]],
            b"<!--EndFragment--></body></html>",
        )
        return data[offsets[b"StartFragment"]:offsets[b"EndFragment"]].decode("utf-8")

    def test_native_table_cells_escape_text_and_preserve_utf8_offsets(self):
        label = "Caf\u00e9 \u6f22\u5b57 \U0001f680"
        document = {"blocks": [{
            "type": "table",
            "headers": [[{"text": "Item"}], [{"text": "Status"}]],
            "rows": [
                [[{"text": label}], [{"text": "Ready", "bold": True}]],
                [[{"text": '<script>& "quoted"'}],
                 [{"text": "  example <file>\nnext", "code": True}]],
            ],
        }]}
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                payload = self.render(runtime, document)
                fragment = self.fragment(payload)
                markup = Markup(fragment)
                for tag, count in {"table": 1, "thead": 1, "tbody": 1, "tr": 3,
                                   "th": 2, "td": 4, "code": 1, "b": 1}.items():
                    self.assertEqual(markup.starts[tag], count, tag)
                    self.assertEqual(markup.ends[tag], count, tag)
                self.assertEqual(markup.starts["p"], 0)
                self.assertEqual(markup.starts["script"], 0)
                self.assertTrue(all(attrs["scope"] == "col" for attrs in markup.attributes["th"]))
                self.assertTrue(all(
                    "background-color:" in attrs["style"] and "font-weight:bold" in attrs["style"]
                    for attrs in markup.attributes["th"]
                ))
                self.assertIn("&lt;script&gt;&amp; &quot;quoted&quot;", fragment)
                self.assertIn("  example &lt;file&gt;<br>next</code>", fragment)
                self.assertEqual(
                    payload["Text"],
                    "Item\tStatus\r\n" + label + '\tReady\r\n<script>& "quoted"\t'
                    "  example <file>\r\nnext",
                )

    def test_mixed_blocks_keep_order_and_legacy_paragraphs_are_identical(self):
        paragraphs = [[{"text": "Before", "bold": True}], [{"text": "After"}]]
        document = {"blocks": [
            {"type": "paragraph", "runs": paragraphs[0]},
            {"type": "table", "headers": [[{"text": "Name"}]],
             "rows": [[[{"text": "Entry"}]]]},
            {"type": "paragraph", "runs": paragraphs[1]},
        ]}
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                payload = self.render(runtime, document)
                fragment = self.fragment(payload)
                self.assertLess(fragment.index("<b>Before</b>"), fragment.index("<table "))
                self.assertLess(fragment.index("</table>"), fragment.index(">After</p>"))
                self.assertEqual(payload["Text"], "Before\r\n\r\nName\r\nEntry\r\n\r\nAfter")
                legacy = self.render(runtime, {"paragraphs": paragraphs})
                blocks = self.render(runtime, {"blocks": [
                    {"type": "paragraph", "runs": runs} for runs in paragraphs
                ]})
                self.assertEqual(legacy, blocks)

    def test_header_only_table_and_empty_cell(self):
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
                payload = self.render(runtime, {"blocks": [{
                    "type": "table", "headers": [[{"text": ""}]], "rows": [],
                }]})
                markup = Markup(self.fragment(payload))
                self.assertEqual(markup.starts["th"], 1)
                self.assertEqual(markup.starts["td"], 0)
                self.assertEqual(payload["Text"], "")

    def test_invalid_table_and_block_shapes_are_rejected(self):
        header = [[{"text": "Name"}]]
        table = {"type": "table", "headers": header, "rows": []}
        invalid = [
            {"blocks": []}, {"blocks": ["paragraph"]}, {"blocks": [{"type": "raw-html"}]},
            {"blocks": [table], "paragraphs": [[{"text": "mixed root"}]]},
            {"blocks": [{"type": "paragraph", "runs": "text"}]},
            {"blocks": [dict(table, headers=[])]},
            {"blocks": [dict(table, rows="not rows")]},
            {"blocks": [dict(table, rows=[[]])]},
            {"blocks": [dict(table, rows=[[header[0], header[0]]])]},
            {"blocks": [dict(table, rows=[["string cell"]])]},
            {"blocks": [dict(table, rows=[[[]]])]},
            {"blocks": [dict(table, rows=[[[{"text": 42}]]])]},
            {"blocks": [dict(table, rows=[[[{"text": "cell", "bold": "true"}]]])]},
            {"blocks": [dict(table, rows=[[[{"text": "NUL\u0000cell"}]]])]},
            {"blocks": [dict(table, html="<table>raw</table>")]},
        ]
        self.write_input(invalid)
        for runtime in RUNTIMES:
            with self.subTest(runtime=runtime):
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
        self.write_input({"blocks": [{
            "type": "table", "headers": [[{"text": "private sample \u6f22\u5b57"}]], "rows": [],
        }]})
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
        # A distinct namespace prevents PowerShell 7 from autoloading real WinForms.
        stub = r"""
Add-Type -TypeDefinition @'
namespace CopilotRichTextClipboardTest {
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
                    stub + "\n" +
                    f"$source = Get-Content -LiteralPath {literal(SCRIPTS / 'RichText.ps1')} -Raw -Encoding UTF8; "
                    "$source = $source.Replace('[System.Windows.Forms.', '[CopilotRichTextClipboardTest.'); "
                    ". ([scriptblock]::Create($source)); " + r"""
$payload = [pscustomobject]@{ Html = 'rendered'; Text = 'fallback' }
Set-RichTextClipboard -Payload $payload
$data = [CopilotRichTextClipboardTest.Clipboard]::Data.Values
if ($data['HTML Format'] -cne 'rendered' -or $data['UnicodeText'] -cne 'fallback' -or
    -not [CopilotRichTextClipboardTest.Clipboard]::Persistent -or $data.Count -ne 2) {
    throw 'Wrong clipboard data or persistence'
}
[CopilotRichTextClipboardTest.Clipboard]::FailWrite = $true
$failed = $false
try { Set-RichTextClipboard -Payload $payload } catch { $failed = $true }
if (-not $failed) { throw 'Clipboard lock was silently ignored' }
[CopilotRichTextClipboardTest.Clipboard]::FailWrite = $false
[CopilotRichTextClipboardTest.Clipboard]::MissingFormat = $true
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
