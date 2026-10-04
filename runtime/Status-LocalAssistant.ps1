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
    [pscustomobject]@{alias=$taskSettings.alias;process_running=[bool]$taskState.process_running;healthy=[bool]$taskState.healthy;ready=[bool]$taskState.ready;controlPlanePoll=$taskPoll;gatewayHealthy=[bool]$taskGateway;version='1.1.0';healthUrl=$taskState.health_url} | ConvertTo-Json
} finally { $env:USERPROFILE = $taskOldProfile }
