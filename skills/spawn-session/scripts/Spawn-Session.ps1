[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkingDirectory,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,62}$')][string]$Name,
    [string]$Model,
    [ValidateSet('windows-terminal', 'kitty')][string]$Terminal,
    [string]$WindowId = '0',
    [string]$KittyAddress,
    [switch]$Yolo,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try {
    if ($PSBoundParameters.ContainsKey('Name') -and
        $Name -cnotmatch '^[a-z0-9][a-z0-9-]{0,62}$') {
        throw 'Name must be 1-63 lowercase letters, digits, or hyphens'
    }
    $directory = (Get-Item -LiteralPath $WorkingDirectory).FullName
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw 'Working directory must be a directory'
    }
    if ($PSBoundParameters.ContainsKey('Model') -and (
        [string]::IsNullOrWhiteSpace($Model) -or $Model -match '[\x00-\x1f]'
    )) {
        throw 'Model must be nonempty and contain no control characters'
    }
    if (-not $Terminal) {
        $Terminal = if ($IsWindows) { 'windows-terminal' } else { 'kitty' }
    }
    if ($Terminal -eq 'windows-terminal' -and -not $IsWindows) {
        throw 'Windows Terminal is only supported on Windows'
    }
    $sessionId = [guid]::NewGuid().ToString()
    if (-not $PSBoundParameters.ContainsKey('Name')) {
        $null = Get-Command node -CommandType Application -ErrorAction Stop
        $nameOutput = & node --disable-warning=ExperimentalWarning (
            Join-Path $PSScriptRoot 'select-session-name.mjs'
        ) $sessionId $directory
        if ($LASTEXITCODE -ne 0) {
            throw 'Automatic naming failed; see the naming diagnostic above. No session was launched'
        }
        $Name = ($nameOutput -join "`n").Trim()
        if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]{0,62}$') {
            throw 'Automatic naming returned an invalid name; no session was launched'
        }
    }
    $childArgs = @(
        '--experimental', '--remote', '--name', $Name,
        '--session-id', $sessionId
    )
    if ($PSBoundParameters.ContainsKey('Model')) { $childArgs += @('--model', $Model) }
    if ($Yolo) { $childArgs += '--yolo' }
    $childEnv = [ordered]@{}
    foreach ($key in @(
        'COPILOT_HOME', 'AGENT_RELAY_DB', 'AGENT_RELAY_DATA_DIR',
        'AGENT_RELAY_PLUGINS', 'AGENT_RELAY_PLUGIN_DIR', 'AGENT_RELAY_ENV_FILE',
        'AGENT_RELAY_PG_HOST', 'AGENT_RELAY_PG_USER', 'AGENT_RELAY_PG_DB',
        'AGENT_RELAY_PG_PORT', 'AGENT_RELAY_PG_SSL', 'AGENT_RELAY_AZURE_TENANT',
        'AZURE_CONFIG_DIR', 'AGENT_RELAY_HOST', 'AGENT_RELAY_WORDLIST_FILE'
    )) {
        $value = [Environment]::GetEnvironmentVariable($key)
        if ($null -ne $value) { $childEnv[$key] = $value }
    }
    $childEnv['AGENT_RELAY_NAME'] = $Name
    if ($Terminal -eq 'windows-terminal') {
        $json = @{ environment = $childEnv; arguments = $childArgs } |
            ConvertTo-Json -Compress -Depth 4
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $script = '$ErrorActionPreference=''Stop''; ' +
            '$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''' +
            $payload + '''))|ConvertFrom-Json; ' +
            'foreach($v in $p.environment.PSObject.Properties){' +
            '[Environment]::SetEnvironmentVariable($v.Name,[string]$v.Value,''Process'')}; ' +
            '& copilot @($p.arguments)'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
        $command = @(
            'wt', '-w', $WindowId, 'new-tab', '--title', $Name, '-d', $directory,
            'pwsh', '-NoExit', '-EncodedCommand', $encoded
        )
    } else {
        if (-not $KittyAddress) { $KittyAddress = $env:KITTY_LISTEN_ON }
        if (-not $KittyAddress) {
            throw 'Kitty requires -KittyAddress or KITTY_LISTEN_ON'
        }
        $command = @(
            'kitten', '@', '--to', $KittyAddress, 'launch', '--type=tab',
            '--keep-focus', '--tab-title', $Name, '--cwd', $directory
        )
        foreach ($key in $childEnv.Keys) {
            $command += @('--env', "$key=$($childEnv[$key])")
        }
        $command += @('--', 'copilot') + $childArgs
    }
    $plan = [ordered]@{
        status = 'planned'
        session_id = $sessionId
        name = $Name
        working_directory = $directory
        terminal = $Terminal
        focus = $(if ($Terminal -eq 'windows-terminal') {
            'may-take-focus'
        } else { 'keep-focus' })
        terminal_handle = $null
        model = $(if ($PSBoundParameters.ContainsKey('Model')) { $Model } else { $null })
        command = $command
    }
    if (-not $DryRun) {
        $copilotHome = if ($env:COPILOT_HOME) {
            $env:COPILOT_HOME
        } else { Join-Path $HOME '.copilot' }
        if (-not (Test-Path -LiteralPath (
            Join-Path $copilotHome 'extensions/agent-relay/extension.mjs'
        ) -PathType Leaf)) {
            throw 'Agent Relay is not installed in the selected Copilot home'
        }
        $required = if ($Terminal -eq 'windows-terminal') {
            @('wt', 'pwsh', 'copilot')
        } else { @('kitten', 'copilot') }
        foreach ($executable in $required) {
            $null = Get-Command $executable -CommandType Application -ErrorAction Stop
        }
        $executable = $command[0]
        $arguments = $command[1..($command.Count - 1)]
        $output = & $executable @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$executable failed with exit code $LASTEXITCODE; inspect tabs before retrying"
        }
        if ($Terminal -eq 'kitty') {
            $handle = ($output -join "`n").Trim()
            if ($handle -notmatch '^\d+$') {
                throw 'Kitty accepted launch but returned no valid window ID; inspect tabs before retrying'
            }
            $plan.terminal_handle = $handle
        }
        $plan.status = 'launched'
    }
    $plan | ConvertTo-Json -Depth 5 -Compress
} catch {
    Write-Error "spawn-session: $($_.Exception.Message)"
    exit 1
}
