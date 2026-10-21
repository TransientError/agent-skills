#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'spawn-session: %s\n' "$*" >&2; exit 1; }

directory=''
name=''
model=''
address="${KITTY_LISTEN_ON:-}"
dry_run=false
while (($#)); do
    case "$1" in
        --working-directory|--name|--model|--kitty-address)
            (($# >= 2)) || fail "$1 requires a value"
            case "$1" in
                --working-directory) directory="$2" ;;
                --name) name="$2" ;;
                --model) model="$2"; [[ -n "${model//[[:space:]]/}" ]] ||
                    fail 'Model must not be empty' ;;
                --kitty-address) address="$2" ;;
            esac
            shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --help)
            printf '%s\n' 'Usage: bash spawn-session.sh --working-directory DIR --name NAME [--model MODEL] [--kitty-address SOCKET] [--dry-run]'
            exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ||
    fail 'Name must be 1-63 lowercase letters, digits, or hyphens'
[[ -n "$directory" && -d "$directory" ]] || fail 'An existing working directory is required'
[[ -n "$address" ]] || fail 'Kitty requires --kitty-address or KITTY_LISTEN_ON'
[[ ! "$model" =~ [[:cntrl:]] ]] || fail 'Model must contain no control characters'
directory="$(cd -- "$directory" && pwd -P)"
command -v node >/dev/null || fail 'Node.js is required (also required by Agent Relay)'
session_id="$(node -e 'console.log(require("node:crypto").randomUUID())')"

command=(kitten @ --to "$address" launch --type=tab --keep-focus
    --tab-title "$name" --cwd "$directory")
for key in COPILOT_HOME AGENT_RELAY_DB AGENT_RELAY_DATA_DIR AGENT_RELAY_PLUGINS AGENT_RELAY_PLUGIN_DIR; do
    if [[ -v "$key" ]]; then
        command+=(--env "$key=${!key}")
    fi
done
command+=(--env "AGENT_RELAY_NAME=$name" -- copilot --experimental --remote
    --name "$name" --session-id "$session_id")
if [[ -n "$model" ]]; then command+=(--model "$model"); fi

status=planned
handle=''
if [[ "$dry_run" == false ]]; then
    [[ -f "${COPILOT_HOME:-$HOME/.copilot}/extensions/agent-relay/extension.mjs" ]] ||
        fail 'Agent Relay is not installed in the selected Copilot home'
    command -v kitten >/dev/null || fail 'kitten is not on PATH'
    command -v copilot >/dev/null || fail 'copilot is not on PATH'
    handle="$("${command[@]}")" ||
        fail 'Kitty launch failed; inspect existing tabs before retrying'
    [[ "$handle" =~ ^[0-9]+$ ]] ||
        fail 'Kitty accepted launch but returned no valid window ID; inspect tabs before retrying'
    status=launched
fi

node -e '
const [status, session_id, name, working_directory, model, handle, ...command] = process.argv.slice(1);
console.log(JSON.stringify({
    status, session_id, name, working_directory, terminal: "kitty",
    focus: "keep-focus", terminal_handle: handle || null, model: model || null, command
}));
' "$status" "$session_id" "$name" "$directory" "$model" "$handle" "${command[@]}"
