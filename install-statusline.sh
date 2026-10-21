#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() { printf 'install-statusline: %s\n' "$*" >&2; exit 1; }
dry_run=false
force=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        --force) force=true ;;
        *) fail 'Usage: bash install-statusline.sh [--dry-run] [--force]' ;;
    esac
done
command -v node >/dev/null || fail 'Node.js 22.5+ is required.'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_dir="$script_dir/config/copilot-statusline"
target="$HOME/.config/copilot-statusline"
copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
[[ -f "$copilot_home/extensions/agent-relay/bin/agent-relay-statusline.mjs" ]] ||
    fail 'Install Agent Relay first (use --no-statusline).'
if command -v bunx >/dev/null; then
    runner=bunx
elif command -v npx >/dev/null; then
    runner=npx
else
    fail 'Install Bun (bunx) or npm (npx) first.'
fi

ours=false
if [[ -L "$target" && -d "$target" ]] &&
    [[ "$(cd -- "$target" && pwd -P)" == "$source_dir" ]]; then
    ours=true
fi
if [[ "$ours" == false && ( -e "$target" || -L "$target" ) && "$force" == false ]]; then
    fail "$target already exists. Use --force to back it up before linking."
fi

# Validate and stage the JSON merge before changing the directory link.
settings="$copilot_home/settings.json"
staged="$(mktemp)"
trap 'rm -f -- "$staged"' EXIT
node - "$settings" "$runner" "$source_dir/settings.json" > "$staged" <<'JS'
const fs = require("node:fs");
const [path, runner, preset] = process.argv.slice(2);
const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 22 || (major === 22 && minor < 5)) throw Error("Node.js 22.5+ is required.");
const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
const read = path => JSON.parse(fs.readFileSync(path, "utf8").replace(/^\uFEFF/, ""));
if (!object(read(preset))) throw Error("Preset must be a JSON object.");
const settings = fs.existsSync(path) ? read(path) : {};
if (!object(settings) || (settings.footer !== undefined && !object(settings.footer))) {
    throw Error("Copilot settings and footer must be JSON objects.");
}
settings.statusLine = { type: "command", command: `${runner} -y copilot-statusline@0.1.24`, padding: 0 };
settings.footer = { ...settings.footer, showCustom: true };
console.log(JSON.stringify(settings, null, 2));
JS
if [[ "$dry_run" == true ]]; then
    printf 'Would link: %s -> %s\nWould merge: %s\nNo files changed.\n' "$target" "$source_dir" "$settings"
    exit 0
fi
if [[ "$ours" == true ]]; then
    printf 'Already linked: %s\n' "$target"
else
    mkdir -p -- "$(dirname -- "$target")"
    backup=''
    if [[ -e "$target" || -L "$target" ]]; then
        backup="$target.$(node -e 'console.log(require("node:crypto").randomUUID())').bak"
        mv -- "$target" "$backup"
        printf 'Backup: %s\n' "$backup"
    fi
    if ! ln -s -- "$source_dir" "$target"; then
        if [[ -n "$backup" ]]; then mv -- "$backup" "$target"; fi
        fail 'Could not create symlink.'
    fi
    printf 'Linked: %s -> %s\n' "$target" "$source_dir"
fi
if [[ -f "$settings" ]] && cmp -s -- "$settings" "$staged"; then
    printf 'Unchanged: %s\n' "$settings"
else
    mkdir -p -- "$copilot_home"
    if [[ -e "$settings" ]]; then
        backup="$settings.$(node -e 'console.log(require("node:crypto").randomUUID())').bak"
        cp -p -- "$settings" "$backup"
        printf 'Backup: %s\n' "$backup"
    fi
    cat -- "$staged" > "$settings"
    printf 'Updated: %s\n' "$settings"
fi
printf '%s\n' 'Installed Nord preset. Restart Copilot if needed.'
