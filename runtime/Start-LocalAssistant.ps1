. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
if (-not $taskSettings.tunnelId) { throw 'Set your own tunnel ID with Set-Connection.ps1 first.' }
$taskCredential = Join-Path $PSScriptRoot 'credentials\tunnel-key.dpapi'
if (-not (Test-Path -LiteralPath $taskCredential)) { throw 'Save your own runtime key with Save-Credential.ps1 first.' }
$taskHash = [Security.Cryptography.SHA256]::Create()
try { $taskMutexSuffix = [BitConverter]::ToString($taskHash.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-','') }
finally { $taskHash.Dispose() }
$taskMutex = New-Object Threading.Mutex($false, ('Local\ChatGPTLocalAssistant-' + $taskMutexSuffix))
$taskAcquired = $false
$taskPtr = [IntPtr]::Zero
$taskOldKey = $env:CONTROL_PLANE_API_KEY
$taskOldProfile = $env:USERPROFILE
try {
    try { $taskAcquired = $taskMutex.WaitOne(30000) } catch [Threading.AbandonedMutexException] { $taskAcquired = $true }
    if (-not $taskAcquired) { throw 'Another startup operation is still running. Check status and retry.' }
    & $taskSettings.nodeExecutable (Join-Path $PSScriptRoot 'prepare-concurrency.mjs') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Per-task configuration hook failed.' }
    $taskGateway = Get-AssistantGateway
    if (-not $taskGateway) {
        Remove-Item Env:CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
        $taskArgs = '"' + (Join-Path $PSScriptRoot 'task-gateway.mjs') + '"'
        $taskProcess = Start-Process -FilePath $taskSettings.nodeExecutable -ArgumentList $taskArgs -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'gateway.stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'gateway.stderr.log')
        $taskGatewayDeadline = (Get-Date).AddSeconds(30)
        do {
            $taskGateway = Get-AssistantGateway
            if ($taskGateway) { break }
            if ($taskProcess.HasExited) { throw 'Local gateway exited. Inspect its private log locally.' }
            Start-Sleep -Milliseconds 300
        } while ((Get-Date) -lt $taskGatewayDeadline)
        if (-not $taskGateway) { throw 'Local gateway did not become healthy.' }
    }
    $taskSecure = ConvertTo-SecureString ((Get-Content -LiteralPath $taskCredential -Raw).Trim())
    $taskPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($taskSecure)
    $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskPtr)
    if ($taskSettings.configHome) { $env:USERPROFILE = $taskSettings.configHome }
    $taskState = Invoke-AssistantTunnel @('runtimes','connect','--alias',$taskSettings.alias,'--profile',$taskSettings.alias,'--profile-dir',(Join-Path $PSScriptRoot 'profiles'),'--tunnel-id',$taskSettings.tunnelId,'--runtime-api-key','env:CONTROL_PLANE_API_KEY','--mcp-server-url',$taskGateway.mcpUrl,'--json')
    $taskDeadline = (Get-Date).AddSeconds(60)
    do {
        $taskStatusRaw = & (Join-Path $PSScriptRoot 'Status-LocalAssistant.ps1')
        $taskStatus = ($taskStatusRaw -join "`n") | ConvertFrom-Json
        if ($taskStatus.process_running -and $taskStatus.healthy -and $taskStatus.ready -and $taskStatus.controlPlanePoll -and $taskStatus.gatewayHealthy) { break }
        if ((Get-Date) -ge $taskDeadline) { break }
        Start-Sleep -Seconds 3
    } while ($true)
    $taskStatus | ConvertTo-Json
    if (-not ($taskStatus.process_running -and $taskStatus.healthy -and $taskStatus.ready -and $taskStatus.controlPlanePoll -and $taskStatus.gatewayHealthy)) { throw 'Connection has not confirmed all health checks. Inspect the private runtime locally.' }
} finally {
    if ($taskPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskPtr) }
    $env:CONTROL_PLANE_API_KEY = $taskOldKey
    $env:USERPROFILE = $taskOldProfile
    if ($taskAcquired) { $taskMutex.ReleaseMutex() }
    $taskMutex.Dispose()
}
