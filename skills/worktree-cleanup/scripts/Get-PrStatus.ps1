<#
.SYNOPSIS
  Look up PR status for branches or PR ids. Provider auto-detected from origin URL.

.DESCRIPTION
  Azure DevOps (visualstudio.com / dev.azure.com)  -> uses `az repos pr`.
  GitHub (github.com)                              -> uses `gh pr`.

  Accepts branch names (-Branch) and/or explicit PR ids (-PrId, e.g. parsed from a
  pr-<id> worktree). Emits one row per input: Query, PrId, Status, Title.

  Status is normalised to: completed | active | abandoned | none | unknown.
  A worktree is safe to delete when Status is completed or abandoned.

.PARAMETER Branch
  One or more source branch names to resolve to their PR.

.PARAMETER PrId
  One or more PR ids to query directly (best for detached pr-<id> review checkouts).

.PARAMETER RepoPath
  Path inside the repo (to read origin url / gh context). Default: current dir.

.EXAMPLE
  ./Get-PrStatus.ps1 -Branch alice/login-fix,bugfix/timeout
.EXAMPLE
  ./Get-PrStatus.ps1 -PrId 1587110,1560879
#>
[CmdletBinding()]
param(
    [string[]]$Branch,
    [int[]]$PrId,
    [string]$RepoPath = '.'
)

$ErrorActionPreference = 'Stop'
$RepoPath = (Resolve-Path $RepoPath).Path

$url = (& git -C $RepoPath remote get-url origin 2>$null).Trim()
if (-not $url) { throw "No origin remote found at $RepoPath." }

# --- detect provider + parse coordinates ---
$provider = $null; $ado = @{}
if ($url -match 'https?://([^./]+)\.visualstudio\.com/(?:DefaultCollection/)?([^/]+)/_git/([^/]+?)(?:\.git)?/?$') {
    $provider = 'ado'
    $ado = @{ OrgUrl = "https://$($Matches[1]).visualstudio.com"; Project = [uri]::UnescapeDataString($Matches[2]); Repo = [uri]::UnescapeDataString($Matches[3]) }
}
elseif ($url -match 'https?://dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+?)(?:\.git)?/?$') {
    $provider = 'ado'
    $ado = @{ OrgUrl = "https://dev.azure.com/$($Matches[1])"; Project = [uri]::UnescapeDataString($Matches[2]); Repo = [uri]::UnescapeDataString($Matches[3]) }
}
elseif ($url -match 'github\.com') {
    $provider = 'github'
}
else { throw "Unrecognised origin host: $url" }

function Normalize-Ado    { param($s) switch ($s) { 'completed' {'completed'} 'active' {'active'} 'abandoned' {'abandoned'} default {'unknown'} } }
function Normalize-GitHub  { param($s,$merged) if ($merged) {'completed'} elseif ($s -eq 'OPEN') {'active'} elseif ($s -eq 'CLOSED') {'abandoned'} else {'unknown'} }

function Query-Ado {
    param([string]$branch, [int]$id)
    if ($id) {
        $j = az repos pr show --id $id --org $ado.OrgUrl -o json 2>$null | ConvertFrom-Json
        if (-not $j) { return [pscustomobject]@{ PrId=$id; Status='unknown'; Title='' } }
        return [pscustomobject]@{ PrId=$j.pullRequestId; Status=(Normalize-Ado $j.status); Title=$j.title }
    }
    $refs = "refs/heads/$branch"
    $j = az repos pr list --source-branch $refs --status all --org $ado.OrgUrl --project $ado.Project --repository $ado.Repo -o json 2>$null | ConvertFrom-Json
    if (-not $j -or $j.Count -eq 0) { return [pscustomobject]@{ PrId=$null; Status='none'; Title='' } }
    $p = $j | Sort-Object pullRequestId -Descending | Select-Object -First 1
    [pscustomobject]@{ PrId=$p.pullRequestId; Status=(Normalize-Ado $p.status); Title=$p.title }
}

function Query-GitHub {
    param([string]$branch, [int]$id)
    if ($id) {
        $j = gh pr view $id --repo (gh repo view --json nameWithOwner -q .nameWithOwner) --json number,state,isMerged,title 2>$null | ConvertFrom-Json
        if (-not $j) { return [pscustomobject]@{ PrId=$id; Status='unknown'; Title='' } }
        return [pscustomobject]@{ PrId=$j.number; Status=(Normalize-GitHub $j.state $j.isMerged); Title=$j.title }
    }
    $j = gh pr list --head $branch --state all --json number,state,isMerged,title 2>$null | ConvertFrom-Json
    if (-not $j -or $j.Count -eq 0) { return [pscustomobject]@{ PrId=$null; Status='none'; Title='' } }
    $p = $j | Sort-Object number -Descending | Select-Object -First 1
    [pscustomobject]@{ PrId=$p.number; Status=(Normalize-GitHub $p.state $p.isMerged); Title=$p.title }
}

Push-Location $RepoPath
try {
    foreach ($id in $PrId) {
        $r = if ($provider -eq 'ado') { Query-Ado -id $id } else { Query-GitHub -id $id }
        [pscustomobject]@{ Query="pr:$id"; PrId=$r.PrId; Status=$r.Status; Title=$r.Title }
    }
    foreach ($b in $Branch) {
        $r = if ($provider -eq 'ado') { Query-Ado -branch $b } else { Query-GitHub -branch $b }
        [pscustomobject]@{ Query=$b; PrId=$r.PrId; Status=$r.Status; Title=$r.Title }
    }
}
finally { Pop-Location }
