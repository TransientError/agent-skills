<#
.SYNOPSIS
    Stop any running VcXsrv and relaunch it with the flags open-in-emacs-wsl
    requires (-ac so WSL can connect with no xauth cookie, listening on TCP).
.DESCRIPTION
    Destructive: killing VcXsrv drops ALL existing X11 client windows, not just
    Emacs. Only run this after the user has explicitly confirmed they're fine
    losing their current VcXsrv windows (e.g. via ask_user) -- never run it
    automatically just because Open-InEmacsWsl.ps1 printed a misconfiguration
    warning.
.EXAMPLE
    ./Restart-VcXsrv.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$existing = Get-Process -Name 'vcxsrv' -ErrorAction SilentlyContinue
if ($existing) {
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$vcxsrvExe = Get-Command 'vcxsrv.exe' -ErrorAction SilentlyContinue
if (-not $vcxsrvExe) {
    $defaultPath = 'C:\Program Files\VcXsrv\vcxsrv.exe'
    if (Test-Path -LiteralPath $defaultPath) { $vcxsrvExe = Get-Item -LiteralPath $defaultPath }
}
if (-not $vcxsrvExe) {
    Write-Error "VcXsrv executable not found. Install it (e.g. 'scoop install vcxsrv') or start it manually."
    exit 1
}

# -multiwindow: windows blend into the Windows desktop instead of one big root window.
# -clipboard: share the clipboard between Windows and X11 apps.
# -wgl: use native OpenGL (faster than Mesa software rendering).
# -ac: disable X11 access control, so WSL can connect with no xauth cookie.
Start-Process -FilePath $vcxsrvExe.Source -ArgumentList '-multiwindow', '-clipboard', '-wgl', '-ac'

$listening = $null
for ($i = 0; $i -lt 10; $i++) {
    $listening = Get-NetTCPConnection -State Listen -LocalPort 6000 -ErrorAction SilentlyContinue
    if ($listening) { break }
    Start-Sleep -Milliseconds 500
}

if ($listening) {
    Write-Host "VcXsrv restarted with -ac and is listening on TCP 6000." -ForegroundColor Green
} else {
    Write-Error "Restarted VcXsrv but it is not listening on TCP port 6000 after waiting. Check its config."
    exit 1
}
