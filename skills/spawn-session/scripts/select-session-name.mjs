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
  const resuming = extra[0] === "--resume";
  const requestedName = extra[1];
  if ((extra.length && !resuming) || extra.length > 2 ||
      (requestedName !== undefined && !/^[a-z0-9][a-z0-9-]{0,62}$/.test(requestedName)) ||
      !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(sessionId ?? "") ||
      !workingDirectory) {
    throw new Error("Usage: select-session-name.mjs SESSION_ID WORKING_DIRECTORY [--resume [NAME]]");
  }
  process.chdir(workingDirectory);
  const env = process.env;
  const childPath = (path) => resolve(path);
  const copilotHome = childPath(env.COPILOT_HOME || join(homedir(), ".copilot"));
  const relayDir = join(copilotHome, "extensions", "agent-relay");
  const pluginDir = childPath(env.AGENT_RELAY_PLUGIN_DIR || join(relayDir, "plugins"));
  const plugins = statSync(pluginDir, { throwIfNoEntry: false })
    ? readdirSync(pluginDir, { withFileTypes: true })
    : [];
  const hasPlugins = env.AGENT_RELAY_PLUGINS?.split(",").some((path) => path.trim()) ||
      plugins.some((entry) => (entry.isFile() && entry.name.endsWith(".mjs")) ||
        (entry.isDirectory() && statSync(join(pluginDir, entry.name, "package.json"),
          { throwIfNoEntry: false })));

  let names;
  let resumedName = requestedName ?? null;
  if (resuming) {
    const stateDir = join(copilotHome, "session-state", sessionId.toLowerCase());
    const history = statSync(join(stateDir, "events.jsonl"), { throwIfNoEntry: false });
    if (!history?.isFile() || history.size === 0) {
      throw new Error(`No saved local history for ${sessionId}; resume must not create a new session`);
    }
    for (const entry of readdirSync(stateDir)) {
      const lock = /^inuse\.([1-9]\d*)\.lock$/.exec(entry);
      if (!lock) continue;
      try {
        process.kill(Number(lock[1]), 0);
      } catch (error) {
        if (error.code === "ESRCH") continue;
        if (error.code !== "EPERM") throw error;
      }
      throw new Error(`Session ${sessionId} is already in use by a local process; connect to it instead`);
    }
    if (!resumedName) {
      try {
        resumedName = readFileSync(join(stateDir, "files", "agent-relay-name.txt"), "utf8").trim() || null;
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
    if (resumedName && !/^[a-z0-9][a-z0-9-]{0,62}$/.test(resumedName)) {
      throw new Error("Saved Relay name is invalid; supply an explicit valid name to resume");
    }
  } else {
    const localWordlist = join(dirname(fileURLToPath(import.meta.url)), "..", "wordlist.local.txt");
    const hasLocalWordlist = !env.AGENT_RELAY_WORDLIST_FILE &&
      statSync(localWordlist, { throwIfNoEntry: false });
    const source = hasLocalWordlist ? localWordlist : join(relayDir, "identity", "wordlist.mjs");
    if (hasLocalWordlist) {
      names = readFileSync(source, "utf8").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    } else {
      const wordlist = await import(pathToFileURL(source).href);
      if (env.AGENT_RELAY_WORDLIST_FILE && typeof wordlist.loadWords !== "function") {
        throw new Error("Installed Relay does not support AGENT_RELAY_WORDLIST_FILE; upgrade Relay first");
      }
      names = typeof wordlist.loadWords === "function" ? wordlist.loadWords({ env }) : wordlist.WORDS;
    }
    if (!Array.isArray(names) || names.length === 0 ||
        names.some((name) => typeof name !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(name)) ||
        new Set(names).size !== names.length) {
      throw new Error(`Wordlist must contain unique valid names and must not be empty: ${source}`);
    }
  }

  const defaultDataDir = process.platform === "win32"
    ? join(env.LOCALAPPDATA || join(homedir(), "AppData", "Local"), "agent-relay")
    : process.platform === "darwin"
      ? join(homedir(), "Library", "Application Support", "agent-relay")
      : join(env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "agent-relay");
  const canonicalDb = childPath(join(env.AGENT_RELAY_DATA_DIR || defaultDataDir, "agent-relay.db"));
  let agents;
  if (hasPlugins) {
    const { loadPlugins } = await import(pathToFileURL(join(relayDir, "plugin-loader.mjs")).href);
    const registry = await loadPlugins({
      env,
      dataDir: dirname(canonicalDb),
      log: (message) => console.error(`spawn-session naming: ${message}`),
      reservedToolNames: ["list_relay_agents", "send_message"],
    });
    if (registry.transport) {
      const transport = registry.transport.create({
        log: (message) => console.error(`spawn-session naming: ${message}`),
      });
      try {
        await transport.init({
          self: { id: sessionId, name: "spawn-session-name-check" },
          credentials: registry.credentials ?? { get: async () => null },
        });
        agents = await transport.listAgents();
        if (!Array.isArray(agents) || agents.some((agent) =>
          !agent || typeof agent.id !== "string" || typeof agent.name !== "string")) {
          throw new Error("Relay transport returned an invalid roster");
        }
      } finally {
        await transport.stop();
      }
    }
  }

  if (!agents) {
    const dbPath = env.AGENT_RELAY_DB
      ? childPath(env.AGENT_RELAY_DB)
      : statSync(canonicalDb, { throwIfNoEntry: false })
        ? canonicalDb
        : join(relayDir, "agent-relay.db");
    if (!statSync(dbPath, { throwIfNoEntry: false })) {
      throw new Error(`Relay registry not found: ${dbPath}. Start Relay first or supply an explicit name`);
    }
    const { DatabaseSync } = await import("node:sqlite");
    const db = new DatabaseSync(dbPath, { readOnly: true });
    try {
      db.exec("PRAGMA busy_timeout = 5000");
      const cutoff = new Date(Date.now() - 30_000).toISOString();
      agents = db.prepare(
        "SELECT id, name FROM agents WHERE last_heartbeat >= ?",
      ).all(cutoff);
    } finally {
      db.close();
    }
  }
  const active = new Set(agents.filter((agent) =>
    agent.id.toLowerCase() !== sessionId.toLowerCase()).map((agent) => agent.name));
  if (resuming) {
    if (agents.some((agent) => agent.id.toLowerCase() === sessionId.toLowerCase())) {
      throw new Error(`Session ${sessionId} is already active; connect to it instead of resuming another copy`);
    }
    if (resumedName && active.has(resumedName)) {
      throw new Error(`Relay name "${resumedName}" is already active; supply an explicit unused name to resume`);
    }
    process.stdout.write(`${JSON.stringify({ name: resumedName })}\n`);
  } else {
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
  }
} catch (error) {
  console.error(`spawn-session naming: ${error.message}`);
  process.exitCode = 1;
}
