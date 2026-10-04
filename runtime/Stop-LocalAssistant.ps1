. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskOldProfile = $env:USERPROFILE
try {
    if ($taskSettings.configHome) { $env:USERPROFILE = $taskSettings.configHome }
    $null = Invoke-AssistantTunnel @('runtimes','stop',$taskSettings.alias,'--json')
    $taskGateway = Get-AssistantGateway
    if ($taskGateway) {
        $null = Invoke-RestMethod -Method Post -Uri ($taskGateway.base + '/shutdown') -Headers @{'X-Local-Assistant-Instance'=$taskGateway.instance} -TimeoutSec 5
        $taskStopDeadline = (Get-Date).AddSeconds(10)
        while ((Get-AssistantGateway) -and (Get-Date) -lt $taskStopDeadline) { Start-Sleep -Milliseconds 250 }
        if (Get-AssistantGateway) { throw 'Gateway is still closing its own tasks. Check its status before restarting.' }
    }
    Write-Output 'Local assistant stopped. Task files remain on disk.'
}
finally { $env:USERPROFILE = $taskOldProfile }
