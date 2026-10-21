[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'config/copilot-statusline'
$target = Join-Path $HOME '.config/copilot-statusline'
$copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
if (-not (Test-Path -LiteralPath (Join-Path $copilotHome 'extensions/agent-relay/bin/agent-relay-statusline.mjs') -PathType Leaf)) {
    throw 'Install Agent Relay first (use --no-statusline).'
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22.5+ is required.' }
$nodeVersion = & node -p 'process.versions.node'
if ($LASTEXITCODE -ne 0 -or [version]$nodeVersion -lt [version]'22.5.0') {
    throw 'Node.js 22.5+ is required.'
}
$runner = if (Get-Command bunx -ErrorAction SilentlyContinue) { 'bunx' }
    elseif (Get-Command npx -ErrorAction SilentlyContinue) { 'npx' }
    else { throw 'Install Bun (bunx) or npm (npx) first.' }
$parent = Split-Path -Parent $target
$existing = if (Test-Path -LiteralPath $parent) {
    Get-ChildItem -LiteralPath $parent -Force | Where-Object Name -eq 'copilot-statusline'
}
$ours = $existing -and $existing.LinkType -in @('Junction', 'SymbolicLink') -and
    [IO.Path]::GetFullPath($existing.Target) -eq [IO.Path]::GetFullPath($source)
if ($existing -and -not $ours -and -not $Force) {
    throw "$target already exists. Use -Force to back it up before linking."
}
$settingsPath = Join-Path $copilotHome 'settings.json'
$settings = if (Test-Path -LiteralPath $settingsPath) {
    Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else { @{} }
$preset = Get-Content -LiteralPath (Join-Path $source 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
if ($preset -isnot [System.Collections.IDictionary] -or
    $settings -isnot [System.Collections.IDictionary] -or
    ($settings.Contains('footer') -and $settings.footer -isnot [System.Collections.IDictionary])) {
    throw 'Preset, Copilot settings, and footer must be JSON objects.'
}
$settings.statusLine = @{ type = 'command'; command = "$runner -y copilot-statusline@0.1.24"; padding = 0 }
if (-not $settings.Contains('footer')) { $settings.footer = @{} }
$settings.footer.showCustom = $true
$json = ($settings | ConvertTo-Json -Depth 100) + "`n"
if ($DryRun) {
    Write-Host "Would link: $target -> $source"
    Write-Host "Would merge: $settingsPath"
    Write-Host 'No files changed.'
    return
}
if ($ours) {
    Write-Host "Already linked: $target"
} else {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $backup = $null
    if ($existing) {
        $backup = "$target.$([guid]::NewGuid()).bak"
        Move-Item -LiteralPath $target -Destination $backup
        Write-Host "Backup: $backup"
    }
    try {
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $target -Target $source | Out-Null
    } catch {
        if ($backup) { Move-Item -LiteralPath $backup -Destination $target }
        throw
    }
    Write-Host "Linked: $target -> $source"
}
if ((Test-Path -LiteralPath $settingsPath) -and
    [IO.File]::ReadAllText($settingsPath) -eq $json) {
    Write-Host "Unchanged: $settingsPath"
} else {
    New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
    if (Test-Path -LiteralPath $settingsPath) {
        $backup = "$settingsPath.$([guid]::NewGuid()).bak"
        Copy-Item -LiteralPath $settingsPath -Destination $backup
        Write-Host "Backup: $backup"
    }
    [IO.File]::WriteAllText($settingsPath, $json, [Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $settingsPath"
}
Write-Host 'Installed Nord preset. Restart Copilot if needed.'
