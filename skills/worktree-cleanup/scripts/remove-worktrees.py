#!/usr/bin/env python3
"""Safely remove git worktrees and (optionally) their local/remote branches.

Linux/mac equivalent of Remove-Worktrees.ps1. DRY-RUN BY DEFAULT.

Safety:
  * Refuses a worktree with tracked uncommitted changes unless --force.
  * Untracked files can be copied out first via --backup-untracked.
  * Local branch deletion uses `git branch -D` (works for squash-merges).
  * Remote deletion (--delete-remote) requires --execute.
  * Prints recovery SHA per branch (git branch <name> <sha>).
  * Copilot-managed worktrees (*copilot-worktrees*) skipped unless --include-managed.
  * Ambiguous leaf name -> skipped, pass full path.

Usage:
  remove-worktrees.py [-C repo] --name N [--name N ...] [--path-like G]
     [--exclude-like G] [--include-managed] [--delete-local-branch]
     [--delete-remote] [--backup-untracked] [--backup-dir D] [--force] [--execute]
"""
import argparse, fnmatch, os, shutil, subprocess, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-C", dest="repo", default=".")
    ap.add_argument("--name", action="append", required=True)
    ap.add_argument("--path-like", default="*")
    ap.add_argument("--exclude-like", default="*copilot-worktrees*")
    ap.add_argument("--include-managed", action="store_true")
    ap.add_argument("--delete-local-branch", action="store_true")
    ap.add_argument("--delete-remote", action="store_true")
    ap.add_argument("--backup-untracked", action="store_true")
    ap.add_argument("--backup-dir", default=None)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--execute", action="store_true")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)

    def g(*a):
        return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)

    backup_dir = args.backup_dir or os.path.join(repo, ".worktree-cleanup-backup")
    mode = "EXECUTE" if args.execute else "DRY-RUN"
    print(f"== remove-worktrees [{mode}] ==")

    # parse worktrees
    wts, cur = [], None
    for line in g("worktree", "list", "--porcelain").stdout.splitlines():
        if line.startswith("worktree "):
            if cur:
                wts.append(cur)
            cur = {"path": line[9:], "branch": "", "detached": False}
        elif line.startswith("branch "):
            cur["branch"] = line[7:].replace("refs/heads/", "", 1)
        elif line == "detached":
            cur["detached"] = True
    if cur:
        wts.append(cur)

    remote_name = (g("remote").stdout.splitlines() or ["origin"])[0]
    norm = lambda p: p.replace("\\", "/")

    scoped = [w for w in wts
              if (args.include_managed or not fnmatch.fnmatch(norm(w["path"]), args.exclude_like))
              and fnmatch.fnmatch(norm(w["path"]), args.path_like)]

    for n in args.name:
        nn = norm(n)
        hits = [w for w in scoped if norm(w["path"]) == nn]
        if not hits:
            hits = [w for w in scoped if os.path.basename(w["path"]) == n]
        if not hits:
            print(f"  SKIP {n}  (no matching worktree in scope)")
            continue
        if len(hits) > 1:
            print(f"  SKIP {n}  (AMBIGUOUS - {len(hits)} matches; pass full path):")
            for w in hits:
                print(f"      {w['path']}")
            continue
        w = hits[0]
        path, branch, detached = w["path"], w["branch"], w["detached"]
        porc = subprocess.run(["git", "-C", path, "status", "--porcelain"],
                              capture_output=True, text=True).stdout.splitlines()
        dirty = [l for l in porc if l and not l.startswith("??")]
        untracked = [l for l in porc if l.startswith("??")]
        sha = g("rev-parse", "--short", branch).stdout.strip() if branch else ""

        print(f"\n  {n}")
        print(f"    path      : {path}")
        print(f"    branch    : {branch or '(detached)'} {'(' + sha + ')' if sha else ''}")
        if dirty:
            print(f"    dirty     : {len(dirty)} tracked change(s)")
        if untracked:
            print(f"    untracked : {len(untracked)} file(s)")

        if (dirty or untracked) and not args.force and not args.backup_untracked:
            print("    -> BLOCKED: has local changes. Use --force or --backup-untracked.")
            continue

        if args.backup_untracked and untracked:
            dest = os.path.join(backup_dir, n)
            print(f"    backup    : {len(untracked)} untracked -> {dest}")
            if args.execute:
                for u in untracked:
                    rel = u[3:].strip().strip('"')
                    src = os.path.join(path, rel)
                    if os.path.exists(src):
                        tgt = os.path.join(dest, rel)
                        os.makedirs(os.path.dirname(tgt), exist_ok=True)
                        shutil.copy2(src, tgt)

        print(f"    action    : git worktree remove {'--force' if args.force else ''}".rstrip())
        if args.execute:
            a = ["worktree", "remove", path] + (["--force"] if args.force else [])
            r = g(*a)
            if r.returncode != 0:
                print(f"    ERROR: {r.stderr.strip()}")
                continue
            print("    removed worktree")

        if args.delete_local_branch and branch and not detached:
            print(f"    action    : git branch -D {branch}   (recover: git branch {branch} {sha})")
            if args.execute:
                print(f"    {g('branch', '-D', branch).stdout.strip()}")

        if args.delete_remote and branch and not detached:
            print(f"    action    : git push {remote_name} --delete {branch}")
            if args.execute:
                print(f"    {g('push', remote_name, '--delete', branch).stderr.strip()}")

    if args.execute:
        g("worktree", "prune")
        print("\n== pruned admin ==")
    else:
        print("\n== DRY-RUN complete. Re-run with --execute to apply. ==")


if __name__ == "__main__":
    main()
