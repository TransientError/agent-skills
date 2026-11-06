function ConvertTo-RichTextRuns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object]$Runs)

    if ($Runs -isnot [array] -or $Runs.Count -eq 0) {
        throw 'Each paragraph or table cell must be a nonempty array of text runs.'
    }
    $htmlRuns = [System.Collections.Generic.List[string]]::new()
    $textRuns = [System.Collections.Generic.List[string]]::new()
    foreach ($run in $Runs) {
        if ($null -eq $run -or $run -isnot [pscustomobject] -or
            $null -eq $run.PSObject.Properties['text'] -or $run.text -isnot [string]) {
            throw 'Each run must have a string text property.'
        }
        foreach ($property in $run.PSObject.Properties) {
            if ($property.Name -cnotin @('text', 'bold', 'code')) {
                throw 'Run properties must be text, bold, or code.'
            }
            if ($property.Name -cne 'text' -and $property.Value -isnot [bool]) {
                throw 'Run formatting flags must be Boolean.'
            }
        }
        if ($run.text.Contains([string][char]0)) {
            throw 'Text must not contain NUL characters (clipboard string terminators).'
        }
        $text = $run.text -replace '\r\n?|\n', "`r`n"
        $escaped = [System.Net.WebUtility]::HtmlEncode($text) -replace '\r\n', '<br>'
        if ($null -ne $run.PSObject.Properties['code'] -and $run.code) {
            $escaped = '<code style="font-family:Consolas,monospace;white-space:pre-wrap">' + $escaped + '</code>'
        }
        if ($null -ne $run.PSObject.Properties['bold'] -and $run.bold) {
            $escaped = '<b>' + $escaped + '</b>'
        }
        $htmlRuns.Add($escaped)
        $textRuns.Add($text)
    }
    [pscustomobject]@{ Html = $htmlRuns -join ''; Text = $textRuns -join '' }
}

function ConvertTo-RichTextPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Document)

    if ($Document -isnot [pscustomobject] -or
        @($Document.PSObject.Properties.Name).Count -ne 1) {
        throw 'Input must contain only a nonempty paragraphs or blocks array.'
    }
    if ($null -ne $Document.PSObject.Properties['paragraphs']) {
        if ($Document.paragraphs -isnot [array] -or $Document.paragraphs.Count -eq 0) {
            throw 'Input must contain only a nonempty paragraphs array.'
        }
        $blocks = @(foreach ($paragraph in $Document.paragraphs) {
            [pscustomobject]@{ type = 'paragraph'; runs = $paragraph }
        })
    } elseif ($null -ne $Document.PSObject.Properties['blocks']) {
        if ($Document.blocks -isnot [array] -or $Document.blocks.Count -eq 0) {
            throw 'Input must contain only a nonempty blocks array.'
        }
        $blocks = $Document.blocks
    } else {
        throw 'Input must contain only a nonempty paragraphs or blocks array.'
    }

    $htmlBlocks = [System.Collections.Generic.List[string]]::new()
    $textBlocks = [System.Collections.Generic.List[string]]::new()
    $cellStyle = 'border:1px solid #808080;padding:6px 8px;vertical-align:top;text-align:left;font-family:Segoe UI,Arial,sans-serif;font-size:11pt;white-space:pre-wrap'
    foreach ($block in $blocks) {
        if ($block -isnot [pscustomobject] -or
            $null -eq $block.PSObject.Properties['type'] -or $block.type -isnot [string]) {
            throw 'Each block must be a paragraph or table object with a string type.'
        }
        if ($block.type -ceq 'paragraph') {
            $properties = @('type', 'runs')
        } elseif ($block.type -ceq 'table') {
            $properties = @('type', 'headers', 'rows')
        } else {
            throw 'Block type must be paragraph or table.'
        }
        if (@($block.PSObject.Properties.Name).Count -ne $properties.Count) {
            throw "Block properties must be $($properties -join ', ')."
        }
        foreach ($property in $block.PSObject.Properties) {
            if ($property.Name -cnotin $properties) {
                throw "Block properties must be $($properties -join ', ')."
            }
        }
        if ($block.type -ceq 'paragraph') {
            $rendered = ConvertTo-RichTextRuns -Runs $block.runs
            $htmlBlocks.Add('<p style="white-space:pre-wrap">' + $rendered.Html + '</p>')
            $textBlocks.Add($rendered.Text)
            continue
        }
        if ($block.headers -isnot [array] -or $block.headers.Count -eq 0 -or
            $block.rows -isnot [array]) {
            throw 'A table must have nonempty headers and a rows array.'
        }
        $headerCells = [System.Collections.Generic.List[string]]::new()
        $headerText = [System.Collections.Generic.List[string]]::new()
        foreach ($cell in $block.headers) {
            $rendered = ConvertTo-RichTextRuns -Runs $cell
            $headerCells.Add('<th scope="col" style="' + $cellStyle +
                ';font-weight:bold;background-color:#f2f2f2">' + $rendered.Html + '</th>')
            $headerText.Add($rendered.Text)
        }
        $htmlRows = [System.Collections.Generic.List[string]]::new()
        $textRows = [System.Collections.Generic.List[string]]::new()
        $textRows.Add($headerText -join "`t")
        foreach ($row in $block.rows) {
            if ($row -isnot [array] -or $row.Count -ne $block.headers.Count) {
                throw 'Every table row must be an array with exactly one cell per header.'
            }
            $cells = [System.Collections.Generic.List[string]]::new()
            $cellText = [System.Collections.Generic.List[string]]::new()
            foreach ($cell in $row) {
                $rendered = ConvertTo-RichTextRuns -Runs $cell
                $cells.Add('<td style="' + $cellStyle + '">' + $rendered.Html + '</td>')
                $cellText.Add($rendered.Text)
            }
            $htmlRows.Add('<tr>' + ($cells -join '') + '</tr>')
            $textRows.Add($cellText -join "`t")
        }
        $htmlBlocks.Add('<table border="1" cellspacing="0" cellpadding="6" style="border-collapse:collapse">' +
            '<thead><tr>' + ($headerCells -join '') + '</tr></thead><tbody>' +
            ($htmlRows -join '') + '</tbody></table>')
        $textBlocks.Add($textRows -join "`r`n")
    }

    $fragment = $htmlBlocks -join ''
    $prefix = '<html><body><!--StartFragment-->'
    $suffix = '<!--EndFragment--></body></html>'
    $template = "Version:0.9`r`nStartHTML:{0:D10}`r`nEndHTML:{1:D10}`r`nStartFragment:{2:D10}`r`nEndFragment:{3:D10}`r`n"
    $utf8 = [System.Text.Encoding]::UTF8
    $startHtml = $utf8.GetByteCount(($template -f 0, 0, 0, 0))
    $startFragment = $startHtml + $utf8.GetByteCount($prefix)
    $endFragment = $startFragment + $utf8.GetByteCount($fragment)
    $endHtml = $endFragment + $utf8.GetByteCount($suffix)
    $header = $template -f $startHtml, $endHtml, $startFragment, $endFragment
    [pscustomobject]@{
        Html = $header + $prefix + $fragment + $suffix
        Text = $textBlocks -join "`r`n`r`n"
    }
}

function Set-RichTextClipboard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Payload)

    Add-Type -AssemblyName System.Windows.Forms
    $data = [System.Windows.Forms.DataObject]::new()
    $data.SetData([System.Windows.Forms.DataFormats]::Html, $Payload.Html)
    $data.SetData([System.Windows.Forms.DataFormats]::UnicodeText, $Payload.Text)
    [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
    if (-not [System.Windows.Forms.Clipboard]::ContainsData([System.Windows.Forms.DataFormats]::Html) -or
        -not [System.Windows.Forms.Clipboard]::ContainsData([System.Windows.Forms.DataFormats]::UnicodeText)) {
        throw 'Clipboard write was attempted, but HTML and UnicodeText formats could not be confirmed.'
    }
}
