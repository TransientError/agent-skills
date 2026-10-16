<#
.SYNOPSIS
    Open a Windows file in GNU Emacs running inside WSL, displayed via VcXsrv.
.DESCRIPTION
    Launches (or reuses) a WSL distro, converts the given Windows path to its
    WSL equivalent, points DISPLAY at the Windows host's VcXsrv X server (found
    dynamically via the WSL default-route gateway, since the WSL2 vEthernet
    host IP can change across reboots), and starts Emacs detached (setsid) so
    it keeps running after this command returns.

    If VcXsrv isn't running at all, this script starts it fresh (via
    Restart-VcXsrv.ps1) with the required flags. If VcXsrv IS running but
    misconfigured (missing -ac / not listening on TCP), it only warns -- it
    never kills an existing VcXsrv, since that would drop the user's other X11
    windows. Restarting a misconfigured VcXsrv requires explicit user
    confirmation (see Restart-VcXsrv.ps1 and SKILL.md).
.PARAMETER Path
    Windows file path to open. Relative paths are resolved against the current
    directory.
.PARAMETER Distro
    WSL distro name to use. Defaults to "Ubuntu".
.EXAMPLE
    ./Open-InEmacsWsl.ps1 -Path 'D:\OneDrive - Microsoft\org-roam\todo.org'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [string]$Distro = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Verify VcXsrv is actually running with the config this script relies on ---
# (access control disabled via -ac, so no xauth cookie is needed; listening on
# TCP so WSL can reach it over the vEthernet host IP).
$vcxsrv = Get-Process -Name 'vcxsrv' -ErrorAction SilentlyContinue

if ($vcxsrv) {
    # Already running: never kill it here (would drop the user's existing X11
    # windows/clients without their say-so). Just warn if the config looks
    # wrong — the agent should ask_user before running Restart-VcXsrv.ps1,
    # since the user can see the actual client count/state at a glance.
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($vcxsrv[0].Id)").CommandLine
    $listening = Get-NetTCPConnection -State Listen -LocalPort 6000 -ErrorAction SilentlyContinue
    if ($cmdLine -notmatch '(^|\s)-ac(\s|$)') {
        Write-Warning "Running VcXsrv does not have '-ac' (disable access control) in its command line: $cmdLine"
        Write-Warning "Emacs may fail to connect without an xauth cookie. See Restart-VcXsrv.ps1 (requires user confirmation first)."
    }
    if (-not $listening) {
        Write-Warning "VcXsrv is running but nothing is listening on TCP port 6000 (check for '-nolisten tcp' or a non-default display number)."
    }
} else {
    # Not running at all: nothing to lose, safe to start it ourselves.
    Write-Host "VcXsrv is not running; starting it." -ForegroundColor Yellow
    & (Join-Path $scriptDir 'Restart-VcXsrv.ps1')
}

$item = Get-Item -LiteralPath $Path -Force
$winPath = $item.FullName

# Convert the Windows path to its WSL equivalent via wslpath, rather than
# hand-rolling drive-letter string replacement (handles UNC/OneDrive paths too).
$wslPath = (wsl -d $Distro -- wslpath -a "$winPath").Trim()
if (-not $wslPath) {
    Write-Error "Failed to resolve WSL path for: $winPath"
    exit 1
}

# The WSL2 vEthernet host IP can change across reboots, so look it up live
# from inside WSL rather than hardcoding it. This is also where VcXsrv (bound
# to all interfaces on Windows) is reachable from. Parsed on the PowerShell
# side (regex) rather than with bash/awk, to dodge nested-quoting bugs across
# the wsl.exe -> bash -lc -> awk boundary.
$routeOutput = (wsl -d $Distro -- ip route show) -join "`n"
$hostIp = $null
if ($routeOutput -match 'default via (\S+)') {
    $hostIp = $Matches[1]
}
if (-not $hostIp) {
    Write-Error "Could not determine WSL host IP (default gateway) for distro '$Distro'. Route output:`n$routeOutput"
    exit 1
}

$display = "${hostIp}:0.0"
$escapedPath = $wslPath.Replace("'", "'\\''")

# setsid detaches Emacs from the launching shell so it survives after this
# command returns; stdout/stderr go to a log for troubleshooting (e.g. if
# VcXsrv isn't reachable at $display).
wsl -d $Distro -- bash -ic "DISPLAY='$display' setsid emacs '$escapedPath' >/tmp/emacs-copilot.log 2>&1 &" | Out-Null

Start-Sleep -Seconds 2

$running = (wsl -d $Distro -- bash -lc "pgrep -a emacs").Trim()
$log = (wsl -d $Distro -- bash -lc "cat /tmp/emacs-copilot.log 2>/dev/null").Trim()

if ($running) {
    Write-Host "Emacs launched (DISPLAY=$display): $running" -ForegroundColor Green
} else {
    Write-Warning "Emacs does not appear to be running. Log output:`n$log"
    Write-Warning "Check that VcXsrv is running with access control disabled and listening on TCP port 6000."
}
