<#
.SYNOPSIS
    Links skill directories from this repo into the global Copilot skills path
    using NTFS junctions (Windows).
.DESCRIPTION
    Discovers directories containing SKILL.md in the repo root and creates
    junctions at ~/.copilot/skills/<name> pointing to each one.
    Existing junctions are re-created; real directories are skipped with a warning.
#>
[CmdletBinding()]
param(
    [switch]$Remove,  # Remove links instead of creating them
    [switch]$Force    # Replace real directories (backs up to <name>.bak first)
)

$ErrorActionPreference = 'Stop'
$repoRoot  = Split-Path -Parent $PSCommandPath
$skillsDest = Join-Path $env:USERPROFILE '.copilot' 'skills'

if (-not (Test-Path $skillsDest)) {
    New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
}

# Editor skills: only link the first one whose binary is found in PATH.
# Add new editor entries here as needed (order = priority).
$editorSkills = @(
    @{ Name = 'neovide'; Binary = 'neovide' }
    # @{ Name = 'nvy';     Binary = 'nvy' }
)

$editorLinked = $false

$skills = Get-ChildItem -Path $repoRoot -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }

if ($skills.Count -eq 0) {
    Write-Warning "No skill directories (containing SKILL.md) found in $repoRoot"
    exit 0
}

foreach ($skill in $skills) {
    $target = Join-Path $skillsDest $skill.Name

    # Editor skill gate: skip if binary missing or another editor already linked
    $editor = $editorSkills | Where-Object { $_.Name -eq $skill.Name }
    if ($editor) {
        if (-not $Remove) {
            if ($editorLinked) {
                Write-Host "Skipped: $($skill.Name) (another editor skill already linked)" -ForegroundColor DarkGray
                continue
            }
            if (-not (Get-Command $editor.Binary -ErrorAction SilentlyContinue)) {
                Write-Host "Skipped: $($skill.Name) ($($editor.Binary) not found in PATH)" -ForegroundColor DarkGray
                continue
            }
        }
    }

    if ($Remove) {
        if (Test-Path $target) {
            $item = Get-Item $target -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                cmd /c rmdir $target 2>$null
                Write-Host "Removed junction: $($skill.Name)" -ForegroundColor Yellow
            } else {
                Write-Warning "Skipping $($skill.Name): $target is a real directory, not a junction"
            }
        } else {
            Write-Host "Already absent: $($skill.Name)" -ForegroundColor DarkGray
        }
        continue
    }

    # Create / recreate junction
    if (Test-Path $target) {
        $item = Get-Item $target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir $target 2>$null
        } elseif ($Force) {
            Remove-Item -Recurse -Force $target
        } else {
            Write-Warning "Skipping $($skill.Name): $target exists and is a real directory (use -Force to override)"
            continue
        }
    }

    cmd /c mklink /J $target $skill.FullName | Out-Null
    Write-Host "Linked: $($skill.Name) -> $($skill.FullName)" -ForegroundColor Green

    if ($editor) { $editorLinked = $true }
}
