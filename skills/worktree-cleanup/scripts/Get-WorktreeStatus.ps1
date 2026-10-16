<#
.SYNOPSIS
  Scan git worktrees and classify cleanup-readiness. Pure git — no ADO/GitHub needed.

.DESCRIPTION
  For every worktree (optionally filtered by -PathLike) reports:
    Branch, Head, Behind/Ahead vs the main ref, whether its content is already
    squash-merged into main (merge-tree no-op), whether its upstream branch still
    exists on the remote, dirty/untracked state, and any PR id parsed from a
    pr-<id> style worktree folder name.

  Squash-merge detection uses `git merge-tree --write-tree <main> <head>`: if the
  merged tree equals main's tree, every change is already in main (typical after an
  ADO/GitHub squash merge, which normal ancestry checks miss).

.PARAMETER RepoPath
  Any path inside the repo / a worktree. Default: current dir.

.PARAMETER MainRef
  Ref treated as "merged into". Default: auto (origin/HEAD, else origin/main, else origin/master).

.PARAMETER PathLike
  Wildcard filter on worktree path (e.g. 'C:/repos/myrepo/*'). Default: all.

.PARAMETER ExcludeLike
  Wildcard of paths to skip. Default '*copilot-worktrees*' (Copilot-managed worktrees).

.PARAMETER IncludeManaged
  Include the ExcludeLike (Copilot-managed) worktrees instead of skipping them.

.PARAMETER Fetch
  Fetch the main ref from origin first, so merge detection is against latest.

.PARAMETER Json
  Emit JSON instead of objects (pipe-friendly for other tools).

.EXAMPLE
  ./Get-WorktreeStatus.ps1 -PathLike 'C:/repos/myrepo/*' -Fetch | Format-Table
.EXAMPLE
  ./Get-WorktreeStatus.ps1 -Json > status.json
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [string]$MainRef,
    [string]$PathLike = '*',
    [string]$ExcludeLike = '*copilot-worktrees*',
    [switch]$IncludeManaged,
    [switch]$Fetch,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function git-c { param([Parameter(ValueFromRemainingArguments)]$a) & git -C $RepoPath @a }

# Resolve repo + a stable dir for repo-wide queries
$RepoPath = (Resolve-Path $RepoPath).Path
$common = (git-c rev-parse --path-format=absolute --git-common-dir).Trim()

# --- resolve main ref ---
if (-not $MainRef) {
    $head = (git-c symbolic-ref --quiet --short refs/remotes/origin/HEAD) 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) { $MainRef = $head.Trim() }
    else {
        foreach ($c in 'origin/main','origin/master','main','master') {
            git-c rev-parse --verify --quiet $c *> $null
            if ($LASTEXITCODE -eq 0) { $MainRef = $c; break }
        }
    }
}
if (-not $MainRef) { throw "Could not resolve a main ref. Pass -MainRef." }

if ($Fetch) {
    $remote = ($MainRef -split '/')[0]
    $branch = ($MainRef -split '/', 2)[1]
    if ($branch) { git-c fetch $remote $branch --no-tags *> $null }
}

$mainTree = (git-c rev-parse "$MainRef^{tree}").Trim()

# --- remote heads (one call) for existence check ---
$remoteName = ($MainRef -split '/')[0]
$remoteHeads = @{}
foreach ($l in (git-c ls-remote --heads $remoteName 2>$null)) {
    if ($l -match 'refs/heads/(.+)$') { $remoteHeads[$Matches[1]] = $true }
}

# --- parse worktrees ---
$records = @(); $cur = $null
foreach ($line in (git-c worktree list --porcelain)) {
    if ($line -like 'worktree *') {
        if ($cur) { $records += $cur }
        $cur = [ordered]@{ Path = $line.Substring(9); Branch = ''; Head = ''; Detached = $false; Bare = $false }
    }
    elseif ($line -like 'HEAD *')    { $cur.Head = $line.Substring(5) }
    elseif ($line -like 'branch *')  { $cur.Branch = ($line.Substring(7) -replace '^refs/heads/', '') }
    elseif ($line -eq 'detached')    { $cur.Detached = $true; $cur.Branch = '(detached)' }
    elseif ($line -eq 'bare')        { $cur.Bare = $true }
}
if ($cur) { $records += $cur }

$out = foreach ($r in $records) {
    if ($r.Bare) { continue }
    if ($r.Path -notlike $PathLike) { continue }
    if (-not $IncludeManaged -and ($r.Path -replace '\\','/') -like $ExcludeLike) { continue }

    $name = Split-Path $r.Path -Leaf
    $head = $r.Head

    # merged? (content already in main)
    $merged = $false
    if ($head) {
        $res = git-c merge-tree --write-tree $MainRef $head 2>$null
        if ($LASTEXITCODE -eq 0 -and ($res | Select-Object -First 1).Trim() -eq $mainTree) { $merged = $true }
    }

    # ahead/behind
    $behind = $ahead = $null
    if ($head) {
        $c = (git-c rev-list --left-right --count "$MainRef...$head" 2>$null) -split '\s+'
        if ($c.Count -ge 2) { $behind = [int]$c[0]; $ahead = [int]$c[1] }
    }

    # remote branch present?
    $remoteState = 'n/a'
    if (-not $r.Detached -and $r.Branch) {
        $remoteState = if ($remoteHeads.ContainsKey($r.Branch)) { 'present' } else { 'deleted' }
    }

    # dirty / untracked
    $porcelain = git -C $r.Path status --porcelain 2>$null
    $dirty = @($porcelain | Where-Object { $_ -and $_ -notmatch '^\?\?' }).Count
    $untracked = @($porcelain | Where-Object { $_ -match '^\?\?' }).Count

    # pr id from folder name  (pr-<id> convention)
    $prId = if ($name -match '^pr[-_]?(\d+)$') { [int]$Matches[1] } else { $null }

    [pscustomobject]@{
        Name        = $name
        Path        = $r.Path
        Branch      = $r.Branch
        Head        = $head.Substring(0, 8)
        Behind      = $behind
        Ahead       = $ahead
        Merged      = $merged
        RemoteState = $remoteState
        Dirty       = $dirty
        Untracked   = $untracked
        PrId        = $prId
    }
}

if ($Json) { $out | ConvertTo-Json -Depth 4 } else { $out }
