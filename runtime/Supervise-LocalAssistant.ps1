param([switch]$Hosted)
. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSupervisorMutex = New-Object Threading.Mutex($false, ('Local\ChatGPTLocalAssistant-Supervisor-' + (Get-AssistantInstanceSuffix)))
$taskOwnSupervisor = $false
$taskEvents = $null
$taskOldProfile = $env:USERPROFILE
$taskGeneration = 0
$taskBackoff = 5
function Save-SupervisorState([string]$State, [hashtable]$Details = @{}) {
    $taskState = @{pid=$PID;state=$State;at=(Get-Date).ToString('o');generation=$taskGeneration;mode='process-exit-events'}
    foreach ($taskKey in $Details.Keys) { $taskState[$taskKey] = $Details[$taskKey] }
    $taskState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'supervisor.state.private.json') -Encoding UTF8
}
try {
    try { $taskOwnSupervisor = $taskSupervisorMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $taskOwnSupervisor = $true }
    if (-not $taskOwnSupervisor) { exit 0 }
    $taskSettings = Get-AssistantSettings
    if ($taskSettings.configHome) { $env:USERPROFILE = $taskSettings.configHome }
    $taskEvents = New-AssistantControlEvents
    if (-not $Hosted) { $null = $taskEvents.Exit.Reset() }
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'manual-stop.private.json')) {
            Save-SupervisorState 'manually-stopped'
            $taskWake = [Threading.WaitHandle]::WaitAny([Threading.WaitHandle[]]@($taskEvents.Resume,$taskEvents.Exit))
            if ($taskWake -eq 1) { break }
            continue
        }
        $taskProcesses = @()
        $taskProcessWaits = @()
        try {
            Save-SupervisorState 'starting'
            & (Join-Path $PSScriptRoot 'Start-LocalAssistant.ps1') -Automatic | Out-Null
            if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'manual-stop.private.json')) { continue }
            $taskProcesses = @(Get-AssistantManagedProcesses)
            foreach ($taskProcess in $taskProcesses) {
                $taskWait = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset)
                $taskWait.SafeWaitHandle.Dispose()
                $taskWait.SafeWaitHandle = New-Object Microsoft.Win32.SafeHandles.SafeWaitHandle($taskProcess.Handle, $false)
                $taskProcessWaits += $taskWait
            }
            $taskGeneration++
            $taskBackoff = 5
            Save-SupervisorState 'watching' @{gatewayPid=$taskProcesses[0].Id;tunnelPid=$taskProcesses[1].Id}
            # Windows signals these handles on exit. No timed polling or health calls.
            $taskWake = [Threading.WaitHandle]::WaitAny([Threading.WaitHandle[]]($taskProcessWaits + @($taskEvents.Stop,$taskEvents.Exit)))
            if ($taskWake -eq 3) { break }
            if ($taskWake -lt 2) {
                $taskRole = if ($taskWake -eq 0) { 'gateway' } else { 'tunnel' }
                $taskExitCode = $null
                try { $taskExitCode = $taskProcesses[$taskWake].ExitCode } catch { }
                Save-SupervisorState 'process-exited' @{role=$taskRole;exitCode=$taskExitCode}
                # Persist only process role, PID and exit code, never CLI output/keys.
                @{at=(Get-Date).ToString('o');role=$taskRole;exitCode=$taskExitCode;pid=$taskProcesses[$taskWake].Id} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'supervisor.events.private.jsonl') -Encoding UTF8
            }
        } catch {
            Save-SupervisorState 'retrying' @{retrySeconds=$taskBackoff;failureType=$_.Exception.GetType().FullName}
            # Backoff applies only after startup failure (e.g. no network at login).
            $taskWake = [Threading.WaitHandle]::WaitAny([Threading.WaitHandle[]]@($taskEvents.Stop,$taskEvents.Exit), ($taskBackoff * 1000))
            if ($taskWake -eq 1) { break }
            $taskBackoff = [Math]::Min(300, $taskBackoff * 2)
        } finally {
            foreach ($taskWait in $taskProcessWaits) { $taskWait.Dispose() }
            foreach ($taskProcess in $taskProcesses) { $taskProcess.Dispose() }
        }
    }
    Save-SupervisorState 'disabled'
    exit 0
} catch {
    if ($taskOwnSupervisor) { Save-SupervisorState 'supervisor-failed' @{failureType=$_.Exception.GetType().FullName} }
    exit 1
} finally {
    $env:USERPROFILE = $taskOldProfile
    if ($taskEvents) { foreach ($taskEvent in $taskEvents.Values) { $taskEvent.Dispose() } }
    if ($taskOwnSupervisor) { $taskSupervisorMutex.ReleaseMutex() }
    $taskSupervisorMutex.Dispose()
}
