---
name: worktree-cleanup
description: >
  Clean up stale git worktrees + branches whose PRs already merged/closed. Detects
  squash-merged branches (ADO + GitHub), checks PR status via az/gh, and removes
  worktrees safely with a dry-run-first, recovery-SHA workflow. Understands the
  pr-<id> review-checkout naming convention. Use when the user says "clean up
  worktrees", "clean workspace", "delete merged worktrees", "prune worktrees",
  "which worktrees can I delete", "clean up pr-* review branches", or similar.
---

# worktree-cleanup

Prune git worktrees whose work already landed (squash-merged) or whose PR closed.
Provider-agnostic: bare git core, PR status via `az` (Azure DevOps) or `gh` (GitHub),
auto-detected from `origin` URL.

## Conventions assumed
- Worktrees live as sibling dirs off a bare clone. Leaf dir name = worktree name.
- **`pr-<id>`** dir name = a review checkout of PR `<id>` (often detached HEAD).
  Scripts parse the id from the folder name automatically.
- **`*copilot-worktrees*`** paths = Copilot-managed. **Skipped by default** in every
  script (`-IncludeManaged` to override). Never delete these by hand.

## Why not just `git branch --merged`
ADO/GitHub **squash-merge** → the branch is never an ancestor of main, so
`--merged` and `merge-base --is-ancestor` report it as unmerged. This skill instead
tests `git merge-tree --write-tree <main> <head>`: if the merged tree == main's tree,
every change is already in main. That's the `Merged` column.

## Scripts (`scripts/`)
Windows: `*.ps1` (PowerShell). Linux/mac: `get-worktree-status.sh` (bash),
`get-pr-status.py` + `remove-worktrees.py` (python3, stdlib only). Same behaviour;
flags differ (`-Name x` vs `--name x`). All read-only except Remove, which is
**dry-run unless `-Execute` / `--execute`**.

### 1. Get-WorktreeStatus.ps1  — classify
```powershell
scripts/Get-WorktreeStatus.ps1 -RepoPath C:\repos\myrepo\main -Fetch | Format-Table
```
Columns: `Merged` (content in main), `Behind/Ahead`, `RemoteState`
(present|deleted — branch still on origin?), `Dirty`/`Untracked`, `PrId` (from pr-<id>).
`-Json` for piping. `-PathLike`/`-ExcludeLike`/`-IncludeManaged` to scope.

**Delete candidates** = `Merged=True` OR `RemoteState=deleted`, AND `Dirty=0`.
Confirm with PR status before deleting when unsure.

### 2. Get-PrStatus.ps1  — confirm PR state
```powershell
scripts/Get-PrStatus.ps1 -RepoPath . -Branch feature/foo,alice/bar   # by branch
scripts/Get-PrStatus.ps1 -RepoPath . -PrId 1587110,1560879          # by pr-<id>
```
Status normalised: `completed | active | abandoned | none | unknown`.
Safe to delete when `completed` or `abandoned`. Needs `az` (ADO) or `gh` (GitHub) auth.

### 3. Remove-Worktrees.ps1  — remove (guarded)
```powershell
# preview (default)
scripts/Remove-Worktrees.ps1 -RepoPath C:\repos\myrepo\main -Name stale-feature,old-bugfix -DeleteLocalBranch
# apply
scripts/Remove-Worktrees.ps1 -RepoPath C:\repos\myrepo\main -Name stale-feature -DeleteLocalBranch -Execute
```
- **Dry-run unless `-Execute`.** Prints plan + recovery SHA per branch.
- Blocks worktrees with local changes unless `-Force` (discard) or `-BackupUntracked`.
- Ambiguous leaf name (same name in >1 scoped worktree) → skipped, pass full path.
- `-DeleteLocalBranch` uses `git branch -D` (works for squash-merges).
- `-DeleteRemote` OFF by default; requires `-Execute`. Only for **your own** branches
  whose PR is merged; never delete other authors' remote branches.

## Recommended workflow
1. `Get-WorktreeStatus -Fetch` → list candidates (`Merged` or `RemoteState=deleted`, clean).
2. For uncertain ones (unmerged content but maybe superseded), `Get-PrStatus` by
   branch; for `pr-<id>` checkouts, by id.
3. `Remove-Worktrees` **dry-run**, eyeball plan + SHAs.
4. Re-run with `-Execute`. Add `-DeleteLocalBranch`; add `-DeleteRemote` only for your
   own merged branches after confirming remote still had it.

## Safety rules
- Never touch `*copilot-worktrees*` (managed) unless explicitly told.
- Never `-DeleteRemote` a branch you don't own or whose PR isn't merged/abandoned.
- A branch with `Ahead>0` and no merged/closed PR = real unmerged work — keep.
- Recovery: local branch → `git branch <name> <sha>` (reflog ~90d). Print appears in
  Remove output.
