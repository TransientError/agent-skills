<#
.SYNOPSIS
    Align GitHub-flavored Markdown table columns so the raw source is readable.
.DESCRIPTION
    Pads every table cell with spaces so the pipes line up vertically. Preserves
    leading indentation, alignment colons in the separator row (:---, :--:, --:),
    and escaped pipes (\|). Operates in place on the given file(s), preserving the
    file's existing line endings (LF or CRLF) and writing UTF-8 without a BOM.
.PARAMETER Path
    One or more Markdown files to format in place.
.EXAMPLE
    ./Format-MarkdownTables.ps1 -Path README.md
.EXAMPLE
    Get-ChildItem *.md | ./Format-MarkdownTables.ps1
.NOTES
    Limitation: any line whose first non-space character is '|' is treated as a
    table row, including such lines inside fenced code blocks. Avoid running on
    files whose code fences contain pipe-leading lines, or strip those first.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string[]]$Path
)

begin {
    $NUL = [char]0

    function Test-TableLine([string]$line) {
        return $line.TrimStart().StartsWith('|')
    }

    function Split-Row([string]$content) {
        $tmp = $content -replace '\\\|', $NUL
        if ($tmp.StartsWith('|')) { $tmp = $tmp.Substring(1) }
        if ($tmp.EndsWith('|'))   { $tmp = $tmp.Substring(0, $tmp.Length - 1) }
        return @($tmp -split '\|' | ForEach-Object { ($_.Trim()) -replace $NUL, '\|' })
    }

    function Test-SeparatorCells([string[]]$cells) {
        if ($cells.Count -eq 0) { return $false }
        foreach ($c in $cells) {
            if ($c -notmatch '^:?-{1,}:?$') { return $false }
        }
        return $true
    }

    function Format-SepCell([string]$orig, [int]$width) {
        $left  = $orig.StartsWith(':')
        $right = $orig.EndsWith(':')
        $inner = [Math]::Max(1, $width - $(if ($left) { 1 } else { 0 }) - $(if ($right) { 1 } else { 0 }))
        $s = $(if ($left) { ':' } else { '' }) + ('-' * $inner) + $(if ($right) { ':' } else { '' })
        if ($s.Length -lt $width) { $s = $s.PadRight($width, '-') }
        return $s
    }
}

process {
    foreach ($file in $Path) {
        if (-not (Test-Path -LiteralPath $file)) {
            Write-Warning "Not found: $file"
            continue
        }

        $raw        = [System.IO.File]::ReadAllText($file)
        $crlf       = $raw.Contains("`r`n")
        $normalized = ($raw -replace "`r`n", "`n") -replace "`r", "`n"
        $lines      = $normalized.Split("`n")

        $out = New-Object System.Collections.Generic.List[string]
        $i = 0
        $n = $lines.Count

        while ($i -lt $n) {
            if (Test-TableLine $lines[$i]) {
                $lead   = $lines[$i]
                $indent = $lead.Substring(0, $lead.Length - $lead.TrimStart().Length)

                $rows = New-Object System.Collections.Generic.List[object]
                $j = $i
                while ($j -lt $n -and (Test-TableLine $lines[$j])) {
                    $rows.Add((Split-Row ($lines[$j].Trim())))
                    $j++
                }

                $ncols = ($rows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
                for ($r = 0; $r -lt $rows.Count; $r++) {
                    if ($rows[$r].Count -lt $ncols) {
                        $rows[$r] = @($rows[$r]) + @('') * ($ncols - $rows[$r].Count)
                    }
                }

                $sepIdx = -1
                for ($r = 0; $r -lt $rows.Count; $r++) {
                    if (Test-SeparatorCells $rows[$r]) { $sepIdx = $r; break }
                }

                $widths = @(3) * $ncols
                for ($r = 0; $r -lt $rows.Count; $r++) {
                    if ($r -eq $sepIdx) { continue }
                    for ($c = 0; $c -lt $ncols; $c++) {
                        if ($rows[$r][$c].Length -gt $widths[$c]) { $widths[$c] = $rows[$r][$c].Length }
                    }
                }

                for ($r = 0; $r -lt $rows.Count; $r++) {
                    $cells = @()
                    for ($c = 0; $c -lt $ncols; $c++) {
                        if ($r -eq $sepIdx) {
                            $cells += Format-SepCell $rows[$r][$c] $widths[$c]
                        } else {
                            $cells += $rows[$r][$c].PadRight($widths[$c])
                        }
                    }
                    $out.Add($indent + '| ' + ($cells -join ' | ') + ' |')
                }

                $i = $j
            } else {
                $out.Add($lines[$i])
                $i++
            }
        }

        $nl  = if ($crlf) { "`r`n" } else { "`n" }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($file, ($out -join $nl), $enc)
        Write-Host "formatted: $file" -ForegroundColor Green
    }
}
