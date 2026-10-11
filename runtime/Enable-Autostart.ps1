. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskName = Get-AssistantSupervisorTaskName
$taskPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskArguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'KeepAlive-LocalAssistant.ps1') + '"'
$taskNativeHost = Join-Path $PSScriptRoot 'assets\keeper-host.exe'
$taskNativeSource = Join-Path $PSScriptRoot 'KeeperHost.cs'
if (Test-Path -LiteralPath $taskNativeSource) {
    if (-not (Test-Path -LiteralPath $taskNativeHost)) { & (Join-Path $PSScriptRoot 'Build-KeeperHost.ps1') | Out-Null }
}
$taskUser = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskScheduler = New-Object -ComObject Schedule.Service
$taskScheduler.Connect()
$taskFolder = $taskScheduler.GetFolder('\')
$taskPrevious = $null
try { $taskPrevious = $taskFolder.GetTask($taskName) } catch { }
if ($taskPrevious) {
    $taskOldArguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Supervise-LocalAssistant.ps1') + '"'
    $taskPreviousAction = $taskPrevious.Definition.Actions.Item(1)
    if (($taskPreviousAction.Path -ne $taskNativeHost) -and ($taskPreviousAction.Arguments -notin @($taskArguments,$taskOldArguments))) { throw 'Supervisor task belongs to another runtime.' }
    $taskPrevious.Xml | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'supervisor.task.backup.private.xml') -Encoding UTF8
    $taskEvents = New-AssistantControlEvents
    try { $null = $taskEvents.Exit.Set() }
    finally { foreach ($taskEvent in $taskEvents.Values) { $taskEvent.Dispose() } }
    $taskDeadline = (Get-Date).AddSeconds(15)
    while ($taskFolder.GetTask($taskName).State -eq 4 -and (Get-Date) -lt $taskDeadline) { Start-Sleep -Milliseconds 200 }
    if ($taskFolder.GetTask($taskName).State -eq 4) { throw 'Existing supervisor is still exiting; retry enable shortly.' }
    $taskFolder.DeleteTask($taskName, 0)
}
try {
    $taskDefinition = $taskScheduler.NewTask(0)
    $taskDefinition.RegistrationInfo.Description = 'Event-driven ChatGPT local assistant supervision. No periodic health checks.'
    $taskDefinition.Principal.UserId = $taskUser
    $taskDefinition.Principal.LogonType = 3
    $taskDefinition.Principal.RunLevel = 0
    $taskDefinition.Settings.Compatibility = 2
    $taskDefinition.Settings.Enabled = $true
    $taskDefinition.Settings.Hidden = $true
    $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
    $taskDefinition.Settings.StopIfGoingOnBatteries = $false
    $taskDefinition.Settings.IdleSettings.StopOnIdleEnd = $false
    $taskDefinition.Settings.ExecutionTimeLimit = 'PT0S'
    $taskDefinition.Settings.MultipleInstances = 2
    $taskDefinition.Settings.RestartCount = 999
    $taskDefinition.Settings.RestartInterval = 'PT1M'
    $taskDefinition.Settings.StartWhenAvailable = $true
    $taskAction = $taskDefinition.Actions.Create(0)
    $taskAction.Path = if (Test-Path -LiteralPath $taskNativeHost) { $taskNativeHost } else { $taskPowerShell }
    $taskAction.Arguments = if ($taskAction.Path -eq $taskNativeHost) { '' } else { $taskArguments }
    $taskAction.WorkingDirectory = $PSScriptRoot
    $taskLogon = $taskDefinition.Triggers.Create(9)
    $taskLogon.UserId = $taskUser
    $taskLogon.Delay = 'PT10S'
    $taskResume = $taskDefinition.Triggers.Create(0)
    $taskResume.Delay = 'PT10S'
    $taskResume.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name="Microsoft-Windows-Power-Troubleshooter"] and (EventID=1)]]</Select></Query></QueryList>'
    # A single installation launch is a scheduler trigger, not a repeating timer.
    $taskInstall = $taskDefinition.Triggers.Create(1)
    $taskInstall.StartBoundary = (Get-Date).AddSeconds(3).ToString('yyyy-MM-ddTHH:mm:ss')
    $null = $taskFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $taskUser, $null, 3, $null)
    if ([string]$taskFolder.GetTask($taskName).Definition.Actions.Item(1).Path -ne [string]$taskAction.Path -or [string]$taskFolder.GetTask($taskName).Definition.Actions.Item(1).Arguments -ne [string]$taskAction.Arguments) { throw 'Registered supervisor action did not match this runtime.' }
} catch {
    if ($taskPrevious) { $null = $taskFolder.RegisterTask($taskName, $taskPrevious.Xml, 6, $taskUser, $null, 3, $null); $null = $taskFolder.GetTask($taskName).Run($null) }
    throw
}
Remove-AssistantStartupShortcuts
$taskSettings.autostart = $true
Save-AssistantSettings $taskSettings
Write-Output 'Current-user event-driven supervision enabled: login/resume startup, no duration limit, restart on failure. No periodic health checks.'
