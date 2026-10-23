[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Message,
    [string]$Title = 'Agent notification',
    [ValidateRange(1, 5)][int]$Priority = 3,
    [string]$TopicFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'topic.local.txt'),
    [string]$Server = 'https://ntfy.sh',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try {
    try {
        $topic = (Get-Content -LiteralPath $TopicFile -Raw -Encoding utf8).Trim()
    } catch {
        throw 'Cannot read the private topic file; create topic.local.txt beside the skill.'
    }
    if ($topic -cnotmatch '^[-_A-Za-z0-9]{1,64}$' -or $topic -ceq 'ntfy-topic-name') {
        throw 'The private topic file must contain one valid non-placeholder topic.'
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { throw 'Message must not be blank.' }
    $uri = $null
    if (-not [Uri]::TryCreate($Server, [UriKind]::Absolute, [ref]$uri) -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/' -or
        -not ($uri.Scheme -eq 'https' -or
            ($uri.Scheme -eq 'http' -and $uri.Host -in @('localhost', '127.0.0.1', '[::1]')))) {
        throw 'Server must be an HTTPS root URL, or HTTP loopback for local tests.'
    }
    $payload = @{
        topic = $topic
        message = $Message
        title = $Title
        priority = $Priority
    } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    if ($bytes.Length -gt 4096) { throw 'Notification payload must not exceed 4096 UTF-8 bytes.' }
    if ($DryRun) {
        '{"status":"planned"}'
        return
    }
    try {
        $response = Invoke-WebRequest -Uri $uri -Method Post -Body $bytes `
            -ContentType 'application/json' -MaximumRedirection 0 -TimeoutSec 15 `
            -SkipHttpErrorCheck
    } catch {
        throw 'Notification request failed; delivery is unconfirmed. Do not retry automatically.'
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Notification request failed (HTTP $($response.StatusCode)); delivery is unconfirmed. Do not retry automatically."
    }
    try {
        $result = $response.Content | ConvertFrom-Json
    } catch {
        throw 'Invalid server response; delivery is unconfirmed. Do not retry automatically.'
    }
    if ($result.event -cne 'message' -or $result.topic -cne $topic -or
        $result.id -isnot [string] -or $result.id -cnotmatch '^[-_A-Za-z0-9]+$') {
        throw 'Server did not confirm publication; delivery is unconfirmed. Do not retry automatically.'
    }
    '{"status":"published"}'
} catch {
    Write-Error "ntfy: $($_.Exception.Message)"
    exit 1
}
