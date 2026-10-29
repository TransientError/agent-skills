#!/bin/sh
set -eu

fail() {
    printf 'neovide: %s\n' "$*" >&2
    exit 1
}

usage() {
    fail 'Usage: neovide-session.sh open FILE [LINE] | close'
}

[ "$#" -ge 1 ] || usage
action=$1
shift
line=
case "$action" in
    open)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
        file=$1
        [ -n "$file" ] || usage
        case "$file" in
            /*) ;;
            *) file="$PWD/$file" ;;
        esac
        if [ "$#" -eq 2 ]; then
            line=$2
            case "$line" in
                ''|*[!0-9]*) fail 'Line must be a positive integer.' ;;
            esac
            # Strip leading zeros so Neovim does not interpret an octal literal.
            while [ "${line#0}" != "$line" ]; do line=${line#0}; done
            [ -n "$line" ] || fail 'Line must be a positive integer.'
        fi
        ;;
    close) [ "$#" -eq 0 ] || usage ;;
    *) usage ;;
esac

session=${COPILOT_AGENT_SESSION_ID:-}
case "$session" in
    ''|*[!a-zA-Z0-9_-]*) fail 'COPILOT_AGENT_SESSION_ID must contain only letters, digits, underscores or hyphens.' ;;
esac
server="/tmp/nvim-copilot-$session"
command -v nvim >/dev/null 2>&1 || fail 'Neovim (nvim) is not on PATH.'

probe() {
    nvim --server "$server" --remote-expr '1' >/dev/null 2>&1
}

if [ "$action" = close ]; then
    if probe; then
        nvim --server "$server" --remote-send '<C-\><C-N>:qa!<CR>' ||
            fail 'Could not close Neovide.'
        printf 'Closed Neovide for session %s.\n' "$session"
    else
        printf 'No Neovide server running for session %s.\n' "$session"
    fi
    exit 0
fi

if ! probe; then
    command -v neovide >/dev/null 2>&1 || fail 'Neovide is not on PATH.'
    neovide --fork -- --listen "$server" >/dev/null 2>&1 </dev/null &
    launcher=$!
    attempts=0
    until probe; do
        if [ "$attempts" -ge 20 ]; then
            kill "$launcher" 2>/dev/null || :
            wait "$launcher" 2>/dev/null || :
            fail 'Neovide server did not become ready within 10 seconds.'
        fi
        sleep 0.5
        attempts=$((attempts + 1))
    done
fi

nvim --server "$server" --remote "$file" || fail 'File could not be opened.'
if [ -n "$line" ]; then
    nvim --server "$server" --remote-expr "cursor($line, 1)" >/dev/null ||
        fail 'Could not jump to the requested line.'
fi
printf 'Opened in Neovide: %s\n' "$file"
