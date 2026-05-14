#!/usr/bin/env bash
#
# Links skill directories from this repo into the global Copilot skills path
# using symlinks (Linux/macOS).
#
# Discovers directories containing SKILL.md in the repo root and creates
# symlinks at ~/.copilot/skills/<name> pointing to each one.
# Existing symlinks are re-created; real directories are skipped with a warning.
#
# Usage:
#   ./link-skills.sh           # create links
#   ./link-skills.sh --remove  # remove links
#   ./link-skills.sh --force   # replace real directories (backs up to <name>.bak)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DEST="$HOME/.copilot/skills"

mkdir -p "$SKILLS_DEST"

REMOVE=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --remove) REMOVE=true ;;
        --force)  FORCE=true ;;
    esac
done

# Editor skills: only link the first one whose binary is found in PATH.
# Add new editor entries here as needed (order = priority).
editor_skills="neovide:neovide"
# editor_skills="neovide:neovide nvy:nvy"

editor_linked=false

is_editor_skill() {
    local skill_name="$1"
    for entry in $editor_skills; do
        [[ "${entry%%:*}" == "$skill_name" ]] && return 0
    done
    return 1
}

get_editor_binary() {
    local skill_name="$1"
    for entry in $editor_skills; do
        if [[ "${entry%%:*}" == "$skill_name" ]]; then
            echo "${entry#*:}"
            return
        fi
    done
}

found=0
for dir in "$REPO_ROOT"/*/; do
    [[ -f "$dir/SKILL.md" ]] || continue
    found=1

    name="$(basename "$dir")"
    target="$SKILLS_DEST/$name"

    # Editor skill gate: skip if binary missing or another editor already linked
    if is_editor_skill "$name" && ! $REMOVE; then
        if $editor_linked; then
            echo "Skipped: $name (another editor skill already linked)"
            continue
        fi
        binary="$(get_editor_binary "$name")"
        if ! command -v "$binary" &>/dev/null; then
            echo "Skipped: $name ($binary not found in PATH)"
            continue
        fi
    fi

    if $REMOVE; then
        if [[ -L "$target" ]]; then
            rm "$target"
            echo "Removed symlink: $name"
        elif [[ -d "$target" ]]; then
            echo "WARNING: Skipping $name: $target is a real directory, not a symlink" >&2
        else
            echo "Already absent: $name"
        fi
        continue
    fi

    # Create / recreate symlink
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -d "$target" ]]; then
        if $FORCE; then
            rm -rf "$target"
        else
            echo "WARNING: Skipping $name: $target exists and is a real directory (use --force to override)" >&2
            continue
        fi
    fi

    ln -s "${dir%/}" "$target"
    echo "Linked: $name -> ${dir%/}"

    is_editor_skill "$name" && editor_linked=true
done

if [[ $found -eq 0 ]]; then
    echo "WARNING: No skill directories (containing SKILL.md) found in $REPO_ROOT" >&2
fi
