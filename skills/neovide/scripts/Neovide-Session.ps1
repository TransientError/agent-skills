[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('open', 'close')]
    [string]$Action,
    [Parameter(Position = 1)]
    [string]$File,
    [Parameter(Position = 2)]
    [ValidateRange(1, 2147483647)]
    [int]$Line
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

try {
    if ($Action -eq 'open') {
        if ([string]::IsNullOrWhiteSpace($File)) { throw 'Open requires a file path.' }
        $File = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($File)
    } elseif ($PSBoundParameters.ContainsKey('File') -or $PSBoundParameters.ContainsKey('Line')) {
        throw 'Close takes no file or line arguments.'
    }

    $session = $env:COPILOT_AGENT_SESSION_ID
    if (-not $session -or $session -cnotmatch '^[a-zA-Z0-9_-]+$') {
        throw 'COPILOT_AGENT_SESSION_ID must contain only letters, digits, underscores or hyphens.'
    }
    $server = if ($IsWindows) { "\\.\pipe\nvim-copilot-$session" } else { "/tmp/nvim-copilot-$session" }
    $null = Get-Command nvim -CommandType Application -ErrorAction Stop

    function Test-Server {
        & nvim --server $server --remote-expr '1' *> $null
        return $LASTEXITCODE -eq 0
    }

    if ($Action -eq 'close') {
        if (Test-Server) {
            & nvim --server $server --remote-send '<C-\><C-N>:qa!<CR>'
            if ($LASTEXITCODE -ne 0) { throw 'Could not close Neovide.' }
            Write-Output "Closed Neovide for session $session."
        } else {
            Write-Output "No Neovide server running for session $session."
        }
        exit 0
    }

    if (-not (Test-Server)) {
        $null = Get-Command neovide -CommandType Application -ErrorAction Stop
        if ($IsWindows) {
            Start-Process neovide -ArgumentList @('--', '--listen', $server)
        } else {
            & neovide --fork -- --listen $server *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Neovide launch failed.' }
        }
        $attempts = 0
        while (-not (Test-Server)) {
            if ($attempts -ge 20) { throw 'Neovide server did not become ready within 10 seconds.' }
            Start-Sleep -Milliseconds 500
            $attempts++
        }
    }

    & nvim --server $server --remote $File
    if ($LASTEXITCODE -ne 0) { throw 'File could not be opened.' }
    if ($PSBoundParameters.ContainsKey('Line')) {
        & nvim --server $server --remote-expr "cursor($Line, 1)" > $null
        if ($LASTEXITCODE -ne 0) { throw 'Could not jump to the requested line.' }
    }
    Write-Output "Opened in Neovide: $File"
} catch {
    Write-Error "neovide: $($_.Exception.Message)"
    exit 1
}
