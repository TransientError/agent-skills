#!/usr/bin/env bash
# Scan git worktrees and classify cleanup-readiness. Pure git.
# Linux/mac equivalent of Get-WorktreeStatus.ps1.
#
# Usage:
#   get-worktree-status.sh [-C repo] [-m main_ref] [-p path_glob] [-x exclude_glob]
#                          [--include-managed] [--fetch] [--json]
# Columns: name branch head behind ahead merged remote(present|deleted|n/a) dirty untracked prid
set -euo pipefail

REPO="."; MAINREF=""; PATHLIKE="*"; EXCLUDE="*copilot-worktrees*"
INCLUDE_MANAGED=0; DOFETCH=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    -C) REPO="$2"; shift 2;;
    -m|--main) MAINREF="$2"; shift 2;;
    -p|--path-like) PATHLIKE="$2"; shift 2;;
    -x|--exclude-like) EXCLUDE="$2"; shift 2;;
    --include-managed) INCLUDE_MANAGED=1; shift;;
    --fetch) DOFETCH=1; shift;;
    --json) JSON=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
g() { git -C "$REPO" "$@"; }

# resolve main ref
if [ -z "$MAINREF" ]; then
  if h=$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    MAINREF="$h"
  else
    for c in origin/main origin/master main master; do
      if g rev-parse --verify --quiet "$c" >/dev/null 2>&1; then MAINREF="$c"; break; fi
    done
  fi
fi
[ -n "$MAINREF" ] || { echo "Could not resolve a main ref. Pass -m." >&2; exit 1; }

if [ "$DOFETCH" -eq 1 ]; then
  rem="${MAINREF%%/*}"; br="${MAINREF#*/}"
  [ "$br" != "$MAINREF" ] && g fetch "$rem" "$br" --no-tags >/dev/null 2>&1 || true
fi

main_tree=$(g rev-parse "${MAINREF}^{tree}")
remote_name="${MAINREF%%/*}"

# remote heads -> lookup file
remote_heads=$(g ls-remote --heads "$remote_name" 2>/dev/null | sed -n 's#.*refs/heads/##p' || true)
has_remote() { printf '%s\n' "$remote_heads" | grep -qxF "$1"; }

# glob match honoring '*'
match() { case "$1" in $2) return 0;; *) return 1;; esac; }

emit_json=0; [ "$JSON" -eq 1 ] && { printf '['; emit_json=1; }
first=1
[ "$JSON" -eq 0 ] && printf '%-28s %-42s %-9s %6s %5s %-6s %-8s %5s %9s %s\n' \
  NAME BRANCH HEAD BEHIND AHEAD MERGED REMOTE DIRTY UNTRACKED PRID

path="" head="" branch="" detached=0 bare=0
process() {
  [ -z "$path" ] && return
  { [ "$bare" -eq 1 ]; } && return
  match "$path" "$PATHLIKE" || return
  if [ "$INCLUDE_MANAGED" -eq 0 ]; then
    p="${path//\\//}"; match "$p" "$EXCLUDE" && return
  fi
  local name merged behind ahead remote dirty untracked prid porc
  name="${path##*/}"
  merged=false
  if [ -n "$head" ]; then
    rt=$(g merge-tree --write-tree "$MAINREF" "$head" 2>/dev/null | head -n1 || true)
    [ "$rt" = "$main_tree" ] && merged=true
  fi
  behind=""; ahead=""
  if [ -n "$head" ]; then
    read -r behind ahead < <(g rev-list --left-right --count "${MAINREF}...${head}" 2>/dev/null | tr '\t' ' ') || true
  fi
  remote="n/a"
  if [ "$detached" -eq 0 ] && [ -n "$branch" ]; then
    if has_remote "$branch"; then remote="present"; else remote="deleted"; fi
  fi
  porc=$(git -C "$path" status --porcelain 2>/dev/null || true)
  dirty=$(printf '%s\n' "$porc" | grep -c -v '^??' 2>/dev/null || true)
  [ -z "$porc" ] && dirty=0
  untracked=$(printf '%s\n' "$porc" | grep -c '^??' 2>/dev/null || true)
  prid=""; case "$name" in pr-[0-9]*|pr_[0-9]*|pr[0-9]*) prid="${name##*[!0-9]}";; esac
  local hs="${head:0:8}"
  if [ "$JSON" -eq 1 ]; then
    [ "$first" -eq 0 ] && printf ','; first=0
    printf '{"name":"%s","path":"%s","branch":"%s","head":"%s","behind":%s,"ahead":%s,"merged":%s,"remote":"%s","dirty":%s,"untracked":%s,"prid":%s}' \
      "$name" "$path" "$branch" "$hs" "${behind:-null}" "${ahead:-null}" "$merged" "$remote" "${dirty:-0}" "${untracked:-0}" "${prid:-null}"
  else
    printf '%-28s %-42s %-9s %6s %5s %-6s %-8s %5s %9s %s\n' \
      "$name" "${branch:-(detached)}" "$hs" "${behind:-.}" "${ahead:-.}" "$merged" "$remote" "${dirty:-0}" "${untracked:-0}" "${prid:-}"
  fi
}

while IFS= read -r line; do
  case "$line" in
    worktree\ *) process; path="${line#worktree }"; head=""; branch=""; detached=0; bare=0;;
    HEAD\ *)     head="${line#HEAD }";;
    branch\ *)   branch="${line#branch refs/heads/}";;
    detached)    detached=1; branch="";;
    bare)        bare=1;;
  esac
done < <(g worktree list --porcelain)
process

[ "$JSON" -eq 1 ] && printf ']\n'
exit 0
