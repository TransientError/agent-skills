#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'spawn-session: %s\n' "$*" >&2; exit 1; }

directory=''
name=''
model=''
address="${KITTY_LISTEN_ON:-}"
dry_run=false
yolo=false
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
        --yolo) yolo=true; shift ;;
        --help)
            printf '%s\n' 'Usage: bash spawn-session.sh --working-directory DIR --name NAME [--model MODEL] [--kitty-address SOCKET] [--yolo] [--dry-run]'
            exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ||
    fail 'Name must be 1-63 lowercase letters, digits, or hyphens'
[[ -n "$directory" && -d "$directory" ]] || fail 'An existing working directory is required'
[[ ! "$model" =~ [[:cntrl:]] ]] || fail 'Model must contain no control characters'
directory="$(cd -- "$directory" && pwd -P)"
command -v node >/dev/null || fail 'Node.js is required (also required by Agent Relay)'
session_id="$(node -e 'console.log(require("node:crypto").randomUUID())')"

kitty_started=false
bootstrap_handle=''
kitty_start_command=()
if [[ "$dry_run" == false ]]; then
    [[ -f "${COPILOT_HOME:-$HOME/.copilot}/extensions/agent-relay/extension.mjs" ]] ||
        fail 'Agent Relay is not installed in the selected Copilot home'
    command -v kitten >/dev/null || fail 'kitten is not on PATH'
    command -v copilot >/dev/null || fail 'copilot is not on PATH'
fi
if [[ -z "$address" ]]; then
    socket_directory="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    if [[ "$dry_run" == false ]]; then
        for socket in "$socket_directory"/spawn-session-kitty-"$UID"-*.sock; do
            [[ -S "$socket" ]] || continue
            if kitten @ --to "unix:$socket" ls >/dev/null 2>&1; then
                address="unix:$socket"
                break
            fi
            printf 'spawn-session: skipping unresponsive Kitty socket: %s\n' "$socket" >&2
        done
    fi
    if [[ -z "$address" ]]; then
        address="unix:$socket_directory/spawn-session-kitty-$UID-$session_id.sock"
        kitty_start_command=(kitty --detach --session none --listen-on "$address"
            -o allow_remote_control=socket-only --directory "$directory")
        if [[ "$dry_run" == false ]]; then
            command -v kitty >/dev/null || fail 'kitty is not on PATH'
            "${kitty_start_command[@]}" >&2 || fail 'Could not start a listening Kitty instance'
            ready=false
            for ((attempt = 0; attempt < 40; attempt++)); do
                if kitten @ --to "$address" ls >/dev/null 2>&1; then
                    ready=true
                    break
                fi
                sleep 0.1
            done
            [[ "$ready" == true ]] ||
                fail "Kitty started but its socket is not ready: $address; inspect the new window before retrying"
            bootstrap_handle="$(kitten @ --to "$address" ls | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => console.log(JSON.parse(input)[0].tabs[0].windows[0].id));
')" || fail "Could not identify the initial Kitty window: $address"
            [[ "$bootstrap_handle" =~ ^[0-9]+$ ]] ||
                fail "Kitty returned no valid initial window ID: $address"
            kitty_started=true
        fi
    fi
fi

command=(kitten @ --to "$address" launch --type=tab --keep-focus
    --tab-title "$name" --cwd "$directory")
for key in COPILOT_HOME AGENT_RELAY_DB AGENT_RELAY_DATA_DIR AGENT_RELAY_PLUGINS AGENT_RELAY_PLUGIN_DIR; do
    if [[ -v "$key" ]]; then
        command+=(--env "$key=$(printenv "$key")")
    fi
done
command+=(--env "AGENT_RELAY_NAME=$name" -- copilot --experimental --remote
    --name "$name" --session-id "$session_id")
if [[ -n "$model" ]]; then command+=(--model "$model"); fi
if [[ "$yolo" == true ]]; then command+=(--yolo); fi

status=planned
handle=''
if [[ "$dry_run" == false ]]; then
    handle="$("${command[@]}")" ||
        fail 'Kitty launch failed; inspect existing tabs before retrying'
    [[ "$handle" =~ ^[0-9]+$ ]] ||
        fail 'Kitty accepted launch but returned no valid window ID; inspect tabs before retrying'
    if [[ "$kitty_started" == true ]]; then
        kitten @ --to "$address" close-window --match "id:$bootstrap_handle" >&2 ||
            fail "Peer launched in window $handle but could not close initial Kitty window $bootstrap_handle; do not relaunch"
    fi
    status=launched
fi

node -e '
const [status, session_id, name, working_directory, model, handle, kitty_address, kitty_started, start_count, ...args] = process.argv.slice(1);
console.log(JSON.stringify({
    status, session_id, name, working_directory, terminal: "kitty",
    focus: kitty_started === "true" ? "new-window-may-take-focus" : "keep-focus",
    terminal_handle: handle || null, model: model || null, kitty_address,
    kitty_started: kitty_started === "true",
    kitty_start_command: args.slice(0, Number(start_count)),
    command: args.slice(Number(start_count))
}));
' "$status" "$session_id" "$name" "$directory" "$model" "$handle" \
    "$address" "$kitty_started" "${#kitty_start_command[@]}" "${kitty_start_command[@]}" "${command[@]}"
