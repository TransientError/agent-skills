<#
.SYNOPSIS
    Links this repo's agents directory into the global Copilot agents path.
.DESCRIPTION
    Windows-only. Creates an NTFS junction at ~/.copilot/agents pointing to
    agents/ in this clone or worktree. Requires no administrator privileges.
    Existing content is left untouched unless -Force is used, which moves it
    to agents.bak first. -Remove removes only a junction pointing to this repo.
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'link-agents.ps1 requires Windows (NTFS junctions).'
}

if ($Remove -and $Force) {
    throw 'Use either -Remove or -Force, not both.'
}

$repoRoot = Split-Path -Parent $PSCommandPath
$agentsRoot = Join-Path $repoRoot 'agents'
$copilotRoot = Join-Path $env:USERPROFILE '.copilot'
$target = Join-Path $copilotRoot 'agents'

# Enumerating the parent also finds junctions whose destination no longer exists.
$existing = if (Test-Path -LiteralPath $copilotRoot) {
    Get-ChildItem -LiteralPath $copilotRoot -Force |
        Where-Object { $_.Name -eq 'agents' }
}
$isOurJunction = $existing -and
    $existing.LinkType -eq 'Junction' -and
    $existing.Target -eq $agentsRoot

if ($Remove) {
    if (-not $existing) {
        Write-Host 'Already absent: agents'
    } elseif ($isOurJunction) {
        [IO.Directory]::Delete($target)
        Write-Host "Removed junction: $target"
    } else {
        throw "$target is not a junction to $agentsRoot; refusing to remove it."
    }
    return
}

if (-not (Test-Path -LiteralPath $agentsRoot -PathType Container)) {
    throw "Agents directory not found: $agentsRoot"
}

if ($isOurJunction) {
    Write-Host "Already linked: $target -> $agentsRoot"
    return
}

if ($existing) {
    if (-not $Force) {
        throw "$target already exists. Use -Force to back it up to agents.bak first."
    }
    $backup = Join-Path $copilotRoot 'agents.bak'
    if (Get-ChildItem -LiteralPath $copilotRoot -Force |
            Where-Object { $_.Name -eq 'agents.bak' }) {
        throw "$backup already exists; move it before using -Force."
    }
    Move-Item -LiteralPath $target -Destination $backup
    Write-Host "Backed up: $target -> $backup"
}

New-Item -ItemType Directory -Path $copilotRoot -Force | Out-Null
New-Item -ItemType Junction -Path $target -Target $agentsRoot | Out-Null
Write-Host "Linked: $target -> $agentsRoot"
