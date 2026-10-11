. (Join-Path $PSScriptRoot 'Common.ps1')
Import-Module (Join-Path $PSHOME 'Modules\ScheduledTasks\ScheduledTasks.psd1') -ErrorAction Stop
$taskName = Get-AssistantSupervisorTaskName
$taskInstalled = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($taskInstalled) {
    $taskExpected = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'KeepAlive-LocalAssistant.ps1') + '"'
    $taskNativeHost = Join-Path $PSScriptRoot 'assets\keeper-host.exe'
    if (($taskInstalled.Actions.Arguments -notcontains $taskExpected) -and ($taskInstalled.Actions.Execute -notcontains $taskNativeHost)) { throw 'Supervisor task belongs to another installation; no change made.' }
    $null = Disable-ScheduledTask -TaskName $taskName
    $taskEvents = New-AssistantControlEvents
    try { $null = $taskEvents.Exit.Set() }
    finally { foreach ($taskEvent in $taskEvents.Values) { $taskEvent.Dispose() } }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Remove-AssistantStartupShortcuts
$taskSettings = Get-AssistantSettings
$taskSettings.autostart = $false
Save-AssistantSettings $taskSettings
Write-Output 'Automatic startup and supervision disabled. Runtime files were preserved.'
