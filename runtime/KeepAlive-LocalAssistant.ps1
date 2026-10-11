. (Join-Path $PSScriptRoot 'Common.ps1')
$taskKeeperMutex = New-Object Threading.Mutex($false, ('Local\ChatGPTLocalAssistant-Keeper-' + (Get-AssistantInstanceSuffix)))
$taskOwnKeeper = $false
$taskEvents = $null
$taskRestarts = 0
function Save-KeeperState([string]$State, [int]$WorkerPid=0) {
    @{pid=$PID;state=$State;workerPid=$WorkerPid;at=(Get-Date).ToString('o');restarts=$taskRestarts;mode='supervisor-exit-events'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'keeper.state.private.json') -Encoding UTF8
}
try {
    try { $taskOwnKeeper=$taskKeeperMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $taskOwnKeeper=$true }
    if (-not $taskOwnKeeper) { exit 0 }
    $taskEvents = New-AssistantControlEvents
    $null = $taskEvents.Exit.Reset()
    $taskPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Supervise-LocalAssistant.ps1') + '" -Hosted'
    while (-not $taskEvents.Exit.WaitOne(0)) {
        $taskWorker = $null
        $taskWait = $null
        try {
            # If the outer keeper was interrupted, adopt its surviving inner
            # supervisor rather than creating a child that immediately loses
            # the singleton mutex and exits in a restart loop.
            $taskSupervisorState = Join-Path $PSScriptRoot 'supervisor.state.private.json'
            if (Test-Path -LiteralPath $taskSupervisorState) {
                try {
                    $taskExistingState = Get-Content -LiteralPath $taskSupervisorState -Raw | ConvertFrom-Json
                    $taskExistingInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskExistingState.pid)
                    if ($taskExistingInfo -and $taskExistingInfo.Name -eq 'powershell.exe' -and $taskExistingInfo.CommandLine.Contains((Join-Path $PSScriptRoot 'Supervise-LocalAssistant.ps1'))) {
                        $taskCandidate = [Diagnostics.Process]::GetProcessById([int]$taskExistingState.pid)
                        $null = $taskCandidate.Handle
                        if ([Math]::Abs(($taskCandidate.StartTime - $taskExistingInfo.CreationDate).TotalSeconds) -le 1) { $taskWorker = $taskCandidate }
                        else { $taskCandidate.Dispose() }
                    }
                } catch { }
            }
            if (-not $taskWorker) { $taskWorker = Start-Process -FilePath $taskPowerShell -ArgumentList $taskArguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru }
            $taskWait = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset)
            $taskWait.SafeWaitHandle.Dispose()
            $taskWait.SafeWaitHandle = New-Object Microsoft.Win32.SafeHandles.SafeWaitHandle($taskWorker.Handle, $false)
            Save-KeeperState 'watching' $taskWorker.Id
            $taskWake = [Threading.WaitHandle]::WaitAny([Threading.WaitHandle[]]@($taskWait,$taskEvents.Exit))
            if ($taskWake -eq 1 -or $taskEvents.Exit.WaitOne(0)) { break }
            $taskRestarts++
            @{at=(Get-Date).ToString('o');role='supervisor';pid=$taskWorker.Id;exitCode=$taskWorker.ExitCode} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'supervisor.events.private.jsonl') -Encoding UTF8
            Save-KeeperState 'restarting'
            # Backoff follows an actual exit, never a periodic health check.
            if ($taskEvents.Exit.WaitOne(1000)) { break }
        } catch {
            Save-KeeperState 'retrying'
            if ($taskEvents.Exit.WaitOne(5000)) { break }
        } finally {
            if ($taskWait) { $taskWait.Dispose() }
            if ($taskWorker) { $taskWorker.Dispose() }
        }
    }
    Save-KeeperState 'disabled'
    exit 0
} finally {
    if ($taskEvents) { foreach ($taskEvent in $taskEvents.Values) { $taskEvent.Dispose() } }
    if ($taskOwnKeeper) { $taskKeeperMutex.ReleaseMutex() }
    $taskKeeperMutex.Dispose()
}
