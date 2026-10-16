<#
.SYNOPSIS
  Safely remove git worktrees and (optionally) their local/remote branches.

.DESCRIPTION
  DRY-RUN BY DEFAULT. Prints the plan and recovery SHAs. Pass -Execute to act.

  Safety:
    * Refuses a worktree with tracked uncommitted changes unless -Force.
    * Untracked files block removal unless -Force (git's own guard) — use
      -BackupUntracked to copy them to -BackupDir first.
    * Local branch deletion (-DeleteLocalBranch) uses -D (works for squash-merges).
    * Remote branch deletion (-DeleteRemote) is OFF unless explicitly set AND -Execute.
    * Always prints each branch tip SHA before deletion so it's recoverable from
      reflog (`git branch <name> <sha>`).

.PARAMETER Name
  Worktree folder name(s) or full path(s) to remove. Required.

.PARAMETER RepoPath
  Path inside the repo. Default: current dir.

.PARAMETER DeleteLocalBranch
  Also delete the local branch each worktree had checked out (skipped if detached).

.PARAMETER DeleteRemote
  Also delete the branch on origin. Requires -Execute. Use with care.

.PARAMETER BackupUntracked
  Copy untracked files out to -BackupDir before removal.

.PARAMETER BackupDir
  Destination for -BackupUntracked. Default: <repo>/.worktree-cleanup-backup.

.PARAMETER Force
  Remove even if the worktree has uncommitted/untracked changes.

.PARAMETER Execute
  Actually perform actions. Without it, everything is a dry-run preview.

.EXAMPLE
  ./Remove-Worktrees.ps1 -Name stale-feature,old-bugfix           # preview
.EXAMPLE
  ./Remove-Worktrees.ps1 -Name stale-feature -DeleteLocalBranch -Execute
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Name,
    [string]$RepoPath = '.',
    [string]$PathLike = '*',
    [string]$ExcludeLike = '*copilot-worktrees*',
    [switch]$IncludeManaged,
    [switch]$DeleteLocalBranch,
    [switch]$DeleteRemote,
    [switch]$BackupUntracked,
    [string]$BackupDir,
    [switch]$Force,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$RepoPath = (Resolve-Path $RepoPath).Path
function git-c { param([Parameter(ValueFromRemainingArguments)]$a) & git -C $RepoPath @a }

if (-not $BackupDir) { $BackupDir = Join-Path $RepoPath '.worktree-cleanup-backup' }
$mode = if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' }
Write-Host "== Remove-Worktrees [$mode] ==" -ForegroundColor Cyan

# map worktrees
$wts = @(); $cur = $null
foreach ($line in (git-c worktree list --porcelain)) {
    if ($line -like 'worktree *') { if ($cur) { $wts += $cur }; $cur = [ordered]@{ Path=$line.Substring(9); Branch=''; Detached=$false } }
    elseif ($line -like 'branch *') { $cur.Branch = ($line.Substring(7) -replace '^refs/heads/','') }
    elseif ($line -eq 'detached')   { $cur.Detached = $true }
}
if ($cur) { $wts += $cur }

$remoteName = (git-c remote) | Select-Object -First 1
if (-not $remoteName) { $remoteName = 'origin' }

# scope: drop managed (copilot-worktrees) unless opted in, then apply PathLike
$norm = { param($p) ($p -replace '\\','/') }
$scoped = $wts | Where-Object {
    $p = & $norm $_.Path
    ($IncludeManaged -or $p -notlike $ExcludeLike) -and $p -like $PathLike
}

foreach ($n in $Name) {
    $nn = & $norm $n
    # exact path first, else unique leaf-name within scope
    $hits = @($scoped | Where-Object { (& $norm $_.Path) -eq $nn })
    if (-not $hits.Count) { $hits = @($scoped | Where-Object { (Split-Path $_.Path -Leaf) -eq $n }) }
    if (-not $hits.Count) { Write-Host "  SKIP $n  (no matching worktree in scope)" -ForegroundColor Yellow; continue }
    if ($hits.Count -gt 1) {
        Write-Host "  SKIP $n  (AMBIGUOUS - $($hits.Count) matches; pass full path):" -ForegroundColor Red
        $hits | ForEach-Object { Write-Host ("      {0}" -f $_.Path) }
        continue
    }
    $wt = $hits[0]

    $path = $wt.Path
    $porcelain = git -C $path status --porcelain 2>$null
    $dirty = @($porcelain | Where-Object { $_ -and $_ -notmatch '^\?\?' })
    $untracked = @($porcelain | Where-Object { $_ -match '^\?\?' })
    $branch = $wt.Branch
    $sha = if ($branch) { (git-c rev-parse --short $branch 2>$null) } else { '' }

    Write-Host ""
    Write-Host ("  {0}" -f $n) -ForegroundColor Green
    Write-Host ("    path      : {0}" -f $path)
    Write-Host ("    branch    : {0} {1}" -f ($(if($branch){$branch}else{'(detached)'}), $(if($sha){"($sha)"}else{''})))
    if ($dirty.Count)     { Write-Host ("    dirty     : {0} tracked change(s)" -f $dirty.Count) -ForegroundColor Yellow }
    if ($untracked.Count) { Write-Host ("    untracked : {0} file(s)" -f $untracked.Count) -ForegroundColor Yellow }

    if (($dirty.Count -or $untracked.Count) -and -not $Force -and -not $BackupUntracked) {
        Write-Host "    -> BLOCKED: has local changes. Use -Force (discard) or -BackupUntracked." -ForegroundColor Red
        if (-not $Execute) { Write-Host "    (dry-run: would block)" }
        continue
    }

    # backup untracked
    if ($BackupUntracked -and $untracked.Count) {
        $dest = Join-Path $BackupDir $n
        Write-Host ("    backup    : {0} untracked -> {1}" -f $untracked.Count, $dest)
        if ($Execute) {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            foreach ($u in $untracked) {
                $rel = ($u -replace '^\?\?\s+','').Trim('"')
                $src = Join-Path $path $rel
                if (Test-Path $src) {
                    $target = Join-Path $dest $rel
                    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
                    Copy-Item $src $target -Force
                }
            }
        }
    }

    # remove worktree
    Write-Host ("    action    : git worktree remove {0}" -f $(if($Force){'--force'}else{''}))
    if ($Execute) {
        $args = @('worktree','remove',$path); if ($Force) { $args += '--force' }
        $o = git-c @args 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "    ERROR: $o" -ForegroundColor Red; continue }
        Write-Host "    removed worktree" -ForegroundColor DarkGray
    }

    # delete local branch
    if ($DeleteLocalBranch -and $branch -and -not $wt.Detached) {
        Write-Host ("    action    : git branch -D {0}   (recover: git branch {0} {1})" -f $branch, $sha)
        if ($Execute) {
            $o = git-c branch -D $branch 2>&1
            Write-Host ("    {0}" -f $o) -ForegroundColor DarkGray
        }
    }

    # delete remote branch
    if ($DeleteRemote -and $branch -and -not $wt.Detached) {
        Write-Host ("    action    : git push {0} --delete {1}" -f $remoteName, $branch) -ForegroundColor Yellow
        if ($Execute) {
            $o = git-c push $remoteName --delete $branch 2>&1
            Write-Host ("    {0}" -f $o) -ForegroundColor DarkGray
        }
    }
}

if ($Execute) { git-c worktree prune | Out-Null; Write-Host "`n== pruned admin ==" -ForegroundColor Cyan }
else { Write-Host "`n== DRY-RUN complete. Re-run with -Execute to apply. ==" -ForegroundColor Cyan }

