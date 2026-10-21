[CmdletBinding(DefaultParameterSetName = 'Close')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Close')]
    [ValidateNotNullOrEmpty()][string]$TabTitle,
    [Parameter(ParameterSetName = 'Close')]
    [ValidateNotNullOrEmpty()][string]$TabRuntimeId,
    [Parameter(ParameterSetName = 'Close')][switch]$DryRun,
    [Parameter(Mandatory, ParameterSetName = 'List')][switch]$List
)

$ErrorActionPreference = 'Stop'
try {
    if (-not $IsWindows) {
        throw 'Closing sessions is currently supported only on Windows Terminal'
    }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    function Get-TerminalTabs {
        $windowCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ClassNameProperty,
            'CASCADIA_HOSTING_WINDOW_CLASS'
        )
        $tabCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children, $windowCondition
        )
        foreach ($window in $windows) {
            $tabs = $window.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants, $tabCondition
            )
            foreach ($tab in $tabs) {
                [pscustomobject]@{
                    title = $tab.Current.Name
                    window_handle = $window.Current.NativeWindowHandle
                    runtime_id = $tab.GetRuntimeId() -join ','
                    element = $tab
                }
            }
        }
    }

    $tabs = @(Get-TerminalTabs)
    if ($List) {
        [ordered]@{
            status = 'listed'
            terminal = 'windows-terminal'
            tabs = @($tabs | Select-Object title, window_handle, runtime_id)
        } | ConvertTo-Json -Depth 4 -Compress
        return
    }
    $targetTabs = @($tabs | Where-Object { $_.title -ceq $TabTitle })
    if ($targetTabs.Count -ne 1) {
        throw "Expected exactly one tab with exact title '$TabTitle'; found $($targetTabs.Count). Use -List to inspect tabs; nothing was closed"
    }
    $target = $targetTabs[0]
    if ($TabRuntimeId -and $target.runtime_id -cne $TabRuntimeId) {
        throw 'Tab identity changed since inspection; nothing was closed. Use -List again'
    }
    $button = $target.element.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            'CloseButton'
        )
    )
    if ($null -eq $button -or $button.Current.Name -cne 'Close Tab' -or
        $button.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button -or
        -not $button.Current.IsEnabled) {
        throw 'Expected an enabled Close Tab button with AutomationId CloseButton; nothing was closed'
    }
    $invoke = [System.Windows.Automation.InvokePattern]$button.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern
    )
    $result = [ordered]@{
        status = 'planned'
        terminal = 'windows-terminal'
        title = $target.title
        window_handle = $target.window_handle
        runtime_id = $target.runtime_id
    }
    if (-not $DryRun) {
        $currentTargets = @(Get-TerminalTabs | Where-Object { $_.title -ceq $TabTitle })
        if ($currentTargets.Count -ne 1 -or
            $currentTargets[0].runtime_id -cne $target.runtime_id) {
            throw 'Tab selection changed before closing; nothing was closed. Use -List again'
        }
        $invoke.Invoke()
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 200
            $remaining = @(Get-TerminalTabs | Where-Object {
                $_.runtime_id -ceq $target.runtime_id -or $_.title -ceq $TabTitle
            })
        } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
        if ($remaining.Count -gt 0) {
            throw 'Close requested but the tab identity or exact title is still present. Inspect the target window for confirmation dialogs; do not retry automatically'
        }
        $result.status = 'closed'
    }
    $result | ConvertTo-Json -Compress
} catch {
    Write-Error "close-session: $($_.Exception.Message)"
    exit 1
}
