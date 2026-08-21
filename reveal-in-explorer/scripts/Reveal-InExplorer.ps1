<#
.SYNOPSIS
    Open Windows File Explorer to the folder containing a file. By default the
    containing folder is opened with nothing selected; pass -Select to highlight
    the file (ready to drag).
.DESCRIPTION
    Opens the *containing directory* of a file. Without -Select, opens the folder
    plainly. With -Select, wraps `explorer /select,"<path>"` so the file is
    highlighted. If the path is a directory, that directory is opened directly.
    Windows-only.
.PARAMETER Path
    File (or directory) to reveal. Relative paths are resolved against the
    current directory.
.PARAMETER Select
    Highlight the file inside its containing folder (uses explorer /select).
    Ignored when Path is a directory.
.EXAMPLE
    ./Reveal-InExplorer.ps1 -Path .\report.md
.EXAMPLE
    ./Reveal-InExplorer.ps1 C:\work\notes\design.md -Select
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [switch]$Select
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Not found: $Path"
    exit 1
}

$item = Get-Item -LiteralPath $Path -Force
$full = $item.FullName

if ($item.PSIsContainer) {
    # A directory: open it directly.
    Invoke-Item -LiteralPath $full
    Write-Host "opened folder: $full" -ForegroundColor Green
} elseif ($Select) {
    # A file, -Select: open containing folder with the file highlighted.
    # Call explorer.exe directly (NOT via Start-Process) so it parses the
    # /select command line itself — Start-Process re-quotes the argument and
    # explorer silently falls back to a default folder.
    [void][System.Diagnostics.Process]::Start('explorer.exe', "/select,`"$full`"")
    Write-Host "revealed (selected) in containing folder: $full" -ForegroundColor Green
} else {
    # A file, default: open the containing folder plainly.
    $dir = [System.IO.Path]::GetDirectoryName($full)
    Invoke-Item -LiteralPath $dir
    Write-Host "opened containing folder: $dir" -ForegroundColor Green
}
