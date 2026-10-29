#!/usr/bin/env bash
#
# Links this repo's agents directory into the global Copilot agents path
# using a directory symlink (Linux/macOS).
#
# Creates a symlink at ~/.copilot/agents (or $COPILOT_HOME/agents) pointing to
# agents/ in this clone or worktree.
# Existing content is left untouched unless --force is used, which moves it
# to agents.bak first. --remove removes only a symlink pointing to this repo.
#
# Usage:
#   ./link-agents.sh           # create symlink
#   ./link-agents.sh --remove  # remove symlink
#   ./link-agents.sh --force   # replace existing path (backs up to agents.bak)

set -euo pipefail

fail() {
    printf 'link-agents.sh: %s\n' "$*" >&2
    exit 1
}

REMOVE=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --remove) REMOVE=true ;;
        --force)  FORCE=true ;;
        *)        fail "Usage: ./link-agents.sh [--remove] [--force]" ;;
    esac
done

if $REMOVE && $FORCE; then
    fail "Use either --remove or --force, not both."
fi

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_ROOT="$REPO_ROOT/agents"
COPILOT_ROOT="${COPILOT_HOME:-$HOME/.copilot}"
TARGET="$COPILOT_ROOT/agents"

is_our_symlink=false
if [[ -L "$TARGET" ]]; then
    link_dest="$(readlink -- "$TARGET")"
    if [[ "$link_dest" == "$AGENTS_ROOT" ]]; then
        is_our_symlink=true
    elif [[ -d "$TARGET" ]] && [[ "$(cd -- "$TARGET" && pwd -P)" == "$AGENTS_ROOT" ]]; then
        is_our_symlink=true
    fi
fi

if $REMOVE; then
    if [[ ! -e "$TARGET" && ! -L "$TARGET" ]]; then
        echo "Already absent: agents"
    elif $is_our_symlink; then
        rm -- "$TARGET"
        echo "Removed symlink: $TARGET"
    else
        fail "$TARGET is not a symlink to $AGENTS_ROOT; refusing to remove it."
    fi
    exit 0
fi

if [[ ! -d "$AGENTS_ROOT" ]]; then
    fail "Agents directory not found: $AGENTS_ROOT"
fi

if $is_our_symlink; then
    echo "Already linked: $TARGET -> $AGENTS_ROOT"
    exit 0
fi

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    if ! $FORCE; then
        fail "$TARGET already exists. Use --force to back it up to agents.bak first."
    fi
    BACKUP="$COPILOT_ROOT/agents.bak"
    if [[ -e "$BACKUP" || -L "$BACKUP" ]]; then
        fail "$BACKUP already exists; move it before using --force."
    fi
    mv -- "$TARGET" "$BACKUP"
    echo "Backed up: $TARGET -> $BACKUP"
fi

mkdir -p -- "$COPILOT_ROOT"
ln -s -- "$AGENTS_ROOT" "$TARGET"
echo "Linked: $TARGET -> $AGENTS_ROOT"
