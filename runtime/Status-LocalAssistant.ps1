. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskOldProfile = $env:USERPROFILE
try {
    if ($taskSettings.configHome) { $env:USERPROFILE = $taskSettings.configHome }
    $taskState = Invoke-AssistantTunnel @('runtimes','status',$taskSettings.alias,'--json')
    $taskPoll = $false
    if ($taskState.health_url) {
        try { $taskProbe = Invoke-AssistantTunnel @('health','--url',$taskState.health_url,'--require-control-plane-poll','--json'); $taskPoll = [bool]$taskProbe.control_plane_poll.ok } catch { $taskPoll = $false }
    }
    $taskGateway = Get-AssistantGateway
    $taskBinding = Get-AssistantTunnelBinding $taskState $taskGateway
    $taskSupervisorRunning = $false
    $taskKeeperRunning = $false
    $taskGuardianRunning = $false
    $taskSupervisorMode = ''
    $taskSupervisorFile = Join-Path $PSScriptRoot 'supervisor.state.private.json'
    if (Test-Path -LiteralPath $taskSupervisorFile) {
        try {
            $taskSupervisor = Get-Content -LiteralPath $taskSupervisorFile -Raw | ConvertFrom-Json
            $taskSupervisorProcess = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskSupervisor.pid)
            $taskSupervisorRunning = [bool]($taskSupervisorProcess -and $taskSupervisorProcess.CommandLine.Contains((Join-Path $PSScriptRoot 'Supervise-LocalAssistant.ps1')))
            if ($taskSupervisorRunning) { $taskSupervisorMode = $taskSupervisor.state }
        } catch { }
    }
    $taskKeeperFile = Join-Path $PSScriptRoot 'keeper.state.private.json'
    if (Test-Path -LiteralPath $taskKeeperFile) {
        try {
            $taskKeeper = Get-Content -LiteralPath $taskKeeperFile -Raw | ConvertFrom-Json
            $taskKeeperProcess = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskKeeper.pid)
            $taskKeeperRunning = [bool]($taskKeeperProcess -and $taskKeeperProcess.CommandLine.Contains((Join-Path $PSScriptRoot 'KeepAlive-LocalAssistant.ps1')))
        } catch { }
    }
    $taskGuardianFile = Join-Path $PSScriptRoot 'guardian.state.private.json'
    if (Test-Path -LiteralPath $taskGuardianFile) {
        try {
            $taskGuardian = Get-Content -LiteralPath $taskGuardianFile -Raw | ConvertFrom-Json
            $taskGuardianInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskGuardian.pid)
            $taskGuardianRunning = [bool]($taskGuardianInfo -and $taskGuardianInfo.ExecutablePath -eq (Join-Path $PSScriptRoot 'assets\keeper-host.exe'))
        } catch { }
    }
    [pscustomobject]@{alias=$taskSettings.alias;process_running=[bool]$taskState.process_running;healthy=[bool]$taskState.healthy;ready=[bool]$taskState.ready;controlPlanePoll=$taskPoll;gatewayHealthy=[bool]$taskGateway;tunnelBindingMatches=[bool]$taskBinding.matches;bindingReason=$taskBinding.reason;version=if ($taskGateway) { $taskGateway.version } else { 'unknown' };healthUrl=$taskState.health_url;supervisor_running=$taskSupervisorRunning;supervisor_state=$taskSupervisorMode;keeper_running=$taskKeeperRunning;guardian_running=$taskGuardianRunning;autostart=[bool]$taskSettings.autostart} | ConvertTo-Json
} finally { $env:USERPROFILE = $taskOldProfile }
