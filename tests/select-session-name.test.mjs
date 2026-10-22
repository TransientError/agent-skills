import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sessionId = "11111111-1111-4111-8111-111111111111";
const names = ["alpha", "bravo", "charlie"];
const start = createHash("sha256").update(sessionId).digest().readUInt32BE(0) % names.length;

function fixture(t, plugin = true) {
  const directory = mkdtempSync(join(tmpdir(), "relay-naming-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const skill = join(directory, "skill");
  const scripts = join(skill, "scripts");
  const home = join(directory, "copilot home");
  const relay = join(home, "extensions", "agent-relay");
  const plugins = join(relay, "plugins");
  mkdirSync(scripts, { recursive: true });
  mkdirSync(plugins, { recursive: true });
  const helper = join(scripts, "select-session-name.mjs");
  copyFileSync(join(root, "skills", "spawn-session", "scripts", "select-session-name.mjs"), helper);
  writeFileSync(join(skill, "wordlist.local.txt"), names.join("\n"));
  const events = join(directory, "events.txt");
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    !key.toUpperCase().startsWith("AGENT_RELAY_") && key.toUpperCase() !== "COPILOT_HOME"));
  Object.assign(env, {
    COPILOT_HOME: home,
    AGENT_RELAY_DATA_DIR: directory,
    NAMING_EVENTS: events,
    NAMING_ROSTER: JSON.stringify([{ id: "remote-peer", name: names[start] }]),
  });
  if (plugin) {
    writeFileSync(join(plugins, "remote.mjs"), "");
    writeFileSync(join(relay, "plugin-loader.mjs"), `
import assert from "node:assert/strict";
import { appendFileSync } from "node:fs";
export async function loadPlugins({ env, dataDir, reservedToolNames }) {
  assert.equal(process.cwd(), env.NAMING_CWD);
  assert.equal(dataDir, env.AGENT_RELAY_DATA_DIR);
  assert(reservedToolNames.includes("send_message"));
  const record = event => appendFileSync(env.NAMING_EVENTS, event + "\\n");
  if (env.NAMING_LOAD_ERROR) throw new Error("plugin load failed");
  if (env.NAMING_LOCAL_PLUGIN) return { transport: null };
  return {
    credentials: { get: async () => "fixture-credential" },
    transport: { create: () => ({
      async init({ self, credentials }) {
        assert.equal(self.id, ${JSON.stringify(sessionId)});
        assert.equal(await credentials.get(), "fixture-credential");
        record("init");
        if (env.NAMING_INIT_ERROR) throw new Error("shared connection failed");
      },
      async listAgents() {
        record("list");
        if (env.NAMING_LIST_ERROR) throw new Error("shared roster failed");
        return JSON.parse(env.NAMING_ROSTER);
      },
      async stop() { record("stop"); },
      async register() { throw new Error("Naming must not register a peer"); },
    }) },
  };
}
`);
  }
  env.NAMING_CWD = directory;
  const run = () => spawnSync(process.execPath, [helper, sessionId, directory], {
    cwd: root, env, encoding: "utf8", timeout: 15000,
  });
  const sqlite = (agents) => {
    const db = new DatabaseSync(join(directory, "agent-relay.db"));
    try {
      db.exec("CREATE TABLE agents (id TEXT, name TEXT, last_heartbeat TEXT)");
      const insert = db.prepare("INSERT INTO agents VALUES (?, ?, ?)");
      for (const agent of agents) insert.run(agent.id, agent.name, agent.heartbeat);
    } finally {
      db.close();
    }
  };
  return { directory, env, events, helper, plugins, run, sqlite };
}

test("shared roster skips a remote collision without consulting local SQLite or registering", (t) => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), names[(start + 1) % names.length]);
  assert.equal(readFileSync(f.events, "utf8"), "init\nlist\nstop\n");
});

test("explicit plugin paths also select from the shared roster", (t) => {
  const f = fixture(t);
  rmSync(join(f.plugins, "remote.mjs"));
  f.env.AGENT_RELAY_PLUGINS = "relative-plugin.mjs";
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), names[(start + 1) % names.length]);
});

test("packaged plugins are detected in the overridden plugin directory", (t) => {
  const f = fixture(t);
  rmSync(join(f.plugins, "remote.mjs"));
  const customPlugins = join(f.directory, "custom plugins");
  mkdirSync(join(customPlugins, "pg-plugin"), { recursive: true });
  writeFileSync(join(customPlugins, "pg-plugin", "package.json"), '{"main":"index.mjs"}');
  f.env.AGENT_RELAY_PLUGIN_DIR = "custom plugins";
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), names[(start + 1) % names.length]);
});

for (const [variable, diagnostic, events] of [
  ["NAMING_LOAD_ERROR", "plugin load failed", null],
  ["NAMING_INIT_ERROR", "shared connection failed", "init\nstop\n"],
  ["NAMING_LIST_ERROR", "shared roster failed", "init\nlist\nstop\n"],
]) {
  test(`${diagnostic} fails closed even when local SQLite is available`, (t) => {
    const f = fixture(t);
    f.env[variable] = "1";
    f.sqlite([]);
    const result = f.run();
    assert.equal(result.status, 1, result.stderr);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, new RegExp(diagnostic));
    if (events) assert.equal(readFileSync(f.events, "utf8"), events);
  });
}

test("shared roster exhaustion fails without an invented name", (t) => {
  const f = fixture(t);
  f.env.NAMING_ROSTER = JSON.stringify(names.map((name) => ({ id: name, name })));
  const result = f.run();
  assert.equal(result.status, 1, result.stderr);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /All 3 names are active/);
});

test("invalid shared roster fails and releases the connection", (t) => {
  const f = fixture(t);
  f.env.NAMING_ROSTER = '{"unexpected":"shape"}';
  const result = f.run();
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /invalid roster/);
  assert.equal(readFileSync(f.events, "utf8"), "init\nlist\nstop\n");
});

test("the same session ID does not collide with itself in the shared roster", (t) => {
  const f = fixture(t);
  f.env.NAMING_ROSTER = JSON.stringify([{ id: sessionId, name: names[start] }]);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), names[start]);
});

for (const plugin of [false, true]) {
  test(`local SQLite selection preserves stale/self filtering (${plugin ? "non-transport plugin" : "no plugin"})`, (t) => {
    const f = fixture(t, plugin);
    if (plugin) f.env.NAMING_LOCAL_PLUGIN = "1";
    f.sqlite([
      { id: "live", name: names[start], heartbeat: new Date().toISOString() },
      { id: "stale", name: names[(start + 1) % names.length], heartbeat: "2000-01-01T00:00:00.000Z" },
      { id: sessionId, name: names[(start + 1) % names.length], heartbeat: new Date().toISOString() },
    ]);
    const before = readFileSync(join(f.directory, "agent-relay.db"));
    const result = f.run();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), names[(start + 1) % names.length]);
    assert.deepEqual(readFileSync(join(f.directory, "agent-relay.db")), before);
  });
}

for (const shell of ["pwsh", "bash"]) {
  test(`${shell} forwards PostgreSQL mesh overrides without exposing passwords in its plan`, (t) => {
    if (shell === "bash" && process.platform === "win32") {
      t.skip("Bash launch validation requires native Linux/macOS, not WSL");
      return;
    }
    if (spawnSync(shell, ["--version"]).error?.code === "ENOENT") {
      t.skip(`${shell} is not installed`);
      return;
    }
    const f = fixture(t, false);
    Object.assign(f.env, {
      AGENT_RELAY_ENV_FILE: join(f.directory, "custom.env"),
      AGENT_RELAY_PG_HOST: "shared.example.invalid",
      AGENT_RELAY_AZURE_TENANT: "fixture-tenant",
      AZURE_CONFIG_DIR: join(f.directory, "azure profile"),
      AGENT_RELAY_PG_PASSWORD: "must-not-appear-in-plan",
    });
    const scripts = join(root, "skills", "spawn-session", "scripts");
    const args = shell === "pwsh"
      ? ["-NoProfile", "-File", join(scripts, "Spawn-Session.ps1"),
        "-WorkingDirectory", f.directory, "-Name", "fixture-peer", "-Terminal", "kitty",
        "-KittyAddress", "unix:fixture", "-DryRun"]
      : [join(scripts, "spawn-session.sh"), "--working-directory", f.directory,
        "--name", "fixture-peer", "--kitty-address", "unix:fixture", "--dry-run"];
    const result = spawnSync(shell, args, { env: f.env, encoding: "utf8", timeout: 15000 });
    assert.equal(result.status, 0, result.stderr);
    const plan = JSON.parse(result.stdout);
    for (const key of ["AGENT_RELAY_ENV_FILE", "AGENT_RELAY_PG_HOST",
      "AGENT_RELAY_AZURE_TENANT", "AZURE_CONFIG_DIR"]) {
      assert(plan.command.includes(`${key}=${f.env[key]}`), key);
    }
    assert(!result.stdout.includes(f.env.AGENT_RELAY_PG_PASSWORD));
  });
}
