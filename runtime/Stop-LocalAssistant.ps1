. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskOldProfile = $env:USERPROFILE
$taskMutex = Get-AssistantMutex
$taskAcquired = $false
try {
    try { $taskAcquired = $taskMutex.WaitOne(120000) } catch [Threading.AbandonedMutexException] { $taskAcquired = $true }
    if (-not $taskAcquired) { throw 'Startup is still running. Retry stop shortly.' }
    @{stoppedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'manual-stop.private.json') -Encoding UTF8
    $taskEvents = New-AssistantControlEvents
    try { $null = $taskEvents.Stop.Set() }
    finally { foreach ($taskEvent in $taskEvents.Values) { $taskEvent.Dispose() } }
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
finally {
    $env:USERPROFILE = $taskOldProfile
    if ($taskAcquired) { $taskMutex.ReleaseMutex() }
    $taskMutex.Dispose()
}
