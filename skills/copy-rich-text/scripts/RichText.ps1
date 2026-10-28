function ConvertTo-RichTextPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Document)

    if ($Document -isnot [pscustomobject] -or
        @($Document.PSObject.Properties.Name).Count -ne 1 -or
        $null -eq $Document.PSObject.Properties['paragraphs'] -or
        $Document.paragraphs -isnot [array] -or $Document.paragraphs.Count -eq 0) {
        throw 'Input must contain only a nonempty paragraphs array.'
    }

    $htmlParagraphs = [System.Collections.Generic.List[string]]::new()
    $textParagraphs = [System.Collections.Generic.List[string]]::new()
    foreach ($paragraph in $Document.paragraphs) {
        if ($paragraph -isnot [array] -or $paragraph.Count -eq 0) {
            throw 'Each paragraph must be a nonempty array of text runs.'
        }
        $htmlRuns = [System.Collections.Generic.List[string]]::new()
        $textRuns = [System.Collections.Generic.List[string]]::new()
        foreach ($run in $paragraph) {
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
            if ($run.code) {
                $escaped = '<code style="font-family:Consolas,monospace;white-space:pre-wrap">' + $escaped + '</code>'
            }
            if ($run.bold) { $escaped = '<b>' + $escaped + '</b>' }
            $htmlRuns.Add($escaped)
            $textRuns.Add($text)
        }
        $htmlParagraphs.Add('<p style="white-space:pre-wrap">' + ($htmlRuns -join '') + '</p>')
        $textParagraphs.Add($textRuns -join '')
    }

    $fragment = $htmlParagraphs -join ''
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
        Text = $textParagraphs -join "`r`n`r`n"
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
