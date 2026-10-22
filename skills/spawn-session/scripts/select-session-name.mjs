import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

try {
  const [major, minor] = process.versions.node.split(".").map(Number);
  if (major < 22 || (major === 22 && minor < 13) || (major === 23 && minor < 5)) {
    throw new Error("Automatic naming requires Node.js 22.13+, 23.5+, or 24+ for read-only SQLite");
  }
  const [sessionId, workingDirectory, ...extra] = process.argv.slice(2);
  if (extra.length || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(sessionId ?? "") ||
      !workingDirectory) {
    throw new Error("Usage: select-session-name.mjs SESSION_ID WORKING_DIRECTORY");
  }
  const env = process.env;
  const childPath = (path) => resolve(workingDirectory, path);
  const copilotHome = childPath(env.COPILOT_HOME || join(homedir(), ".copilot"));
  const relayDir = join(copilotHome, "extensions", "agent-relay");
  const pluginDir = childPath(env.AGENT_RELAY_PLUGIN_DIR || join(relayDir, "plugins"));
  const plugins = statSync(pluginDir, { throwIfNoEntry: false })
    ? readdirSync(pluginDir, { withFileTypes: true })
    : [];
  if (env.AGENT_RELAY_PLUGINS?.split(",").some((path) => path.trim()) ||
      plugins.some((entry) => (entry.isFile() && entry.name.endsWith(".mjs")) ||
        (entry.isDirectory() && statSync(join(pluginDir, entry.name, "package.json"),
          { throwIfNoEntry: false })))) {
    throw new Error("Automatic naming supports plugin-free local Relay only; supply an explicit name for plugin-configured meshes");
  }

  const localWordlist = join(dirname(fileURLToPath(import.meta.url)), "..", "wordlist.local.txt");
  const hasLocalWordlist = statSync(localWordlist, { throwIfNoEntry: false });
  const source = hasLocalWordlist ? localWordlist : join(relayDir, "identity", "wordlist.mjs");
  const names = hasLocalWordlist
    ? readFileSync(source, "utf8").split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
    : (await import(pathToFileURL(source).href)).WORDS;
  if (!Array.isArray(names) || names.length === 0 ||
      names.some((name) => typeof name !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(name)) ||
      new Set(names).size !== names.length) {
    throw new Error(`Wordlist must contain unique valid names and must not be empty: ${source}`);
  }

  const defaultDataDir = process.platform === "win32"
    ? join(env.LOCALAPPDATA || join(homedir(), "AppData", "Local"), "agent-relay")
    : process.platform === "darwin"
      ? join(homedir(), "Library", "Application Support", "agent-relay")
      : join(env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "agent-relay");
  const canonicalDb = childPath(join(env.AGENT_RELAY_DATA_DIR || defaultDataDir, "agent-relay.db"));
  const dbPath = env.AGENT_RELAY_DB
    ? childPath(env.AGENT_RELAY_DB)
    : statSync(canonicalDb, { throwIfNoEntry: false })
      ? canonicalDb
      : join(relayDir, "agent-relay.db");
  if (!statSync(dbPath, { throwIfNoEntry: false })) {
    throw new Error(`Relay registry not found: ${dbPath}. Start local Relay first or supply an explicit name`);
  }

  const { DatabaseSync } = await import("node:sqlite");
  const db = new DatabaseSync(dbPath, { readOnly: true });
  let active;
  try {
    db.exec("PRAGMA busy_timeout = 5000");
    const cutoff = new Date(Date.now() - 30_000).toISOString();
    active = new Set(db.prepare(
      "SELECT name FROM agents WHERE last_heartbeat >= ? AND id != ?",
    ).all(cutoff, sessionId).map((agent) => agent.name));
  } finally {
    db.close();
  }
  const start = createHash("sha256").update(sessionId.toLowerCase()).digest().readUInt32BE(0) % names.length;
  let selected;
  for (let offset = 0; offset < names.length; offset++) {
    const candidate = names[(start + offset) % names.length];
    if (!active.has(candidate)) {
      selected = candidate;
      break;
    }
  }
  if (!selected) throw new Error(`All ${names.length} names are active; no session was launched`);
  process.stdout.write(`${selected}\n`);
} catch (error) {
  console.error(`spawn-session naming: ${error.message}`);
  process.exitCode = 1;
}
