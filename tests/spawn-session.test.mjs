import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scripts = join(root, "skills", "spawn-session", "scripts");
const hasPwsh = spawnSync("pwsh", ["-NoProfile", "-Command", "exit 0"]).status === 0;
const hasBash = process.platform !== "win32" &&
  spawnSync("bash", ["--version"]).status === 0;

for (const runtime of ["pwsh", "bash"]) {
  const available = runtime === "pwsh" ? hasPwsh : hasBash;
  function run(agent, terminal = "kitty") {
    const args = runtime === "pwsh"
      ? ["-NoProfile", "-File", join(scripts, "Spawn-Session.ps1"),
        "-WorkingDirectory", root, "-Name", "test-peer", "-Terminal", terminal,
        "-KittyAddress", "unix:/unused", "-DryRun"]
      : [join(scripts, "spawn-session.sh"), "--working-directory", root,
        "--name", "test-peer", "--kitty-address", "unix:/unused", "--dry-run"];
    if (agent !== undefined) args.push(runtime === "pwsh" ? "-Agent" : "--agent", agent);
    return spawnSync(runtime, args, { encoding: "utf8", timeout: 15000 });
  }

  test(`${runtime}: agent selection is optional and passed literally`, { skip: !available }, () => {
    for (const agent of [undefined, "doc-review", "plugin:reviewer's profile; $literal"]) {
      const result = run(agent);
      assert.equal(result.status, 0, result.stderr);
      const plan = JSON.parse(result.stdout);
      assert.equal(plan.agent, agent ?? null);
      const index = plan.command.indexOf("--agent");
      if (agent === undefined) {
        assert.equal(index, -1);
      } else {
        assert.notEqual(index, -1);
        assert.equal(plan.command[index + 1], agent);
      }
    }
  });

  test(`${runtime}: invalid agent values fail before launch`, { skip: !available }, () => {
    for (const agent of ["", "   ", "doc\nreview", "doc\u007freview"]) {
      const result = run(agent);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Agent must/i);
      assert.equal(result.stdout.trim(), "");
    }
  });

  test(`${runtime}: Windows Terminal payload preserves agent`, {
    skip: !available || runtime !== "pwsh" || process.platform !== "win32",
  }, () => {
    const agent = "plugin:reviewer's profile; $literal";
    const result = run(agent, "windows-terminal");
    assert.equal(result.status, 0, result.stderr);
    const plan = JSON.parse(result.stdout);
    assert.equal(plan.agent, agent);
    const encoded = plan.command[plan.command.indexOf("-EncodedCommand") + 1];
    const script = Buffer.from(encoded, "base64").toString("utf16le");
    const payload = script.match(/FromBase64String\('([^']+)'\)/);
    assert.ok(payload);
    const child = JSON.parse(Buffer.from(payload[1], "base64").toString("utf8"));
    assert.equal(child.arguments[child.arguments.indexOf("--agent") + 1], agent);
  });
}
