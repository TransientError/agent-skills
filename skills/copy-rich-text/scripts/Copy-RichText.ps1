[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'RichText.ps1')
    $path = (Resolve-Path -LiteralPath $InputPath).ProviderPath
    try {
        $document = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw 'Cannot read input as UTF-8 JSON. Check the file and JSON syntax.'
    }
    $payload = ConvertTo-RichTextPayload -Document $document
    $windowsDesktop = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    if (-not $windowsDesktop -and -not $DryRun) {
        throw 'Clipboard writing requires an interactive Windows desktop.'
    }
    if ($windowsDesktop -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $scriptLiteral = $PSCommandPath.Replace("'", "''")
        $inputLiteral = $path.Replace("'", "''")
        $command = "& '$scriptLiteral' -InputPath '$inputLiteral'"
        if ($DryRun) { $command += ' -DryRun' }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -EncodedCommand $encoded
        if ($LASTEXITCODE -ne 0) { throw 'STA clipboard process failed; copying is unconfirmed.' }
        return
    }
    if ($DryRun) {
        [pscustomobject]@{
            status = 'planned'
            htmlBytes = [System.Text.Encoding]::UTF8.GetByteCount($payload.Html)
        } | ConvertTo-Json -Compress
        return
    }
    Set-RichTextClipboard -Payload $payload
    '{"status":"copied","formats":["HTML Format","UnicodeText"]}'
} catch {
    Write-Error "copy-rich-text: $($_.Exception.Message)"
    exit 1
}
