$ErrorActionPreference = 'Stop'
# When Windows PowerShell is launched from PowerShell 7, inherited PSModulePath
# can otherwise resolve an incompatible Security module. Use this host's module.
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
function Get-AssistantSettings {
    $taskFile = Join-Path $PSScriptRoot 'settings.private.json'
    if (-not (Test-Path -LiteralPath $taskFile)) { throw 'Run the kit installer first.' }
    Get-Content -LiteralPath $taskFile -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Save-AssistantSettings($Settings) {
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.private.json') -Encoding UTF8
}
function Get-AssistantInstanceSuffix {
    $taskHash = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($taskHash.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-','') }
    finally { $taskHash.Dispose() }
}
function Get-AssistantMutex {
    New-Object Threading.Mutex($false, ('Local\ChatGPTLocalAssistant-' + (Get-AssistantInstanceSuffix)))
}
function Get-AssistantSupervisorTaskName {
    'ChatGPTLocalAssistant-' + (Get-AssistantInstanceSuffix).Substring(0,16)
}
function New-AssistantControlEvents {
    $taskEventRoot = 'Local\ChatGPTLocalAssistant-' + (Get-AssistantInstanceSuffix)
    @{
        Stop = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, ($taskEventRoot + '-Stop'))
        Resume = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, ($taskEventRoot + '-Resume'))
        Exit = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, ($taskEventRoot + '-Exit'))
    }
}
function Resume-AssistantSupervisor {
    # COM avoids PowerShell 5/7 module resolution differences. Missing old task is OK.
    $taskService = New-Object -ComObject Schedule.Service
    $taskService.Connect()
    try {
        $taskRegistered = $taskService.GetFolder('\').GetTask((Get-AssistantSupervisorTaskName))
        if ($taskRegistered.State -ne 4) { $null = $taskRegistered.Run($null) }
    } catch { }
}
function Remove-AssistantStartupShortcuts {
    $taskShell = New-Object -ComObject WScript.Shell
    foreach ($taskName in @('ChatGPT Local Assistant.lnk','ChatGPT Local Files.lnk')) {
        $taskPath = Join-Path ([Environment]::GetFolderPath('Startup')) $taskName
        if (Test-Path -LiteralPath $taskPath) {
            $taskLink = $taskShell.CreateShortcut($taskPath)
            if ($taskLink.WorkingDirectory -eq $PSScriptRoot -and $taskLink.Arguments.Contains($PSScriptRoot)) { Remove-Item -LiteralPath $taskPath }
        }
    }
}
function Get-AssistantManagedProcesses {
    $taskSettings = Get-AssistantSettings
    $taskGateway = Get-AssistantGateway
    if (-not $taskGateway) { throw 'Gateway is not ready for process supervision.' }
    $taskRuntime = Invoke-AssistantTunnel @('runtimes','status',$taskSettings.alias,'--json')
    if (-not $taskRuntime.process_running -or -not $taskRuntime.process.pid) { throw 'Tunnel process is not ready for supervision.' }
    $taskGatewayInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskGateway.pid)
    $taskTunnelInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$taskRuntime.process.pid)
    $taskGatewayPath = Join-Path $PSScriptRoot 'task-gateway.mjs'
    $taskProfilePath = Join-Path $PSScriptRoot 'profiles'
    if (-not $taskGatewayInfo -or $taskGatewayInfo.Name -ne 'node.exe' -or -not $taskGatewayInfo.CommandLine.Contains($taskGatewayPath)) { throw 'Gateway process ownership check failed.' }
    if (-not $taskTunnelInfo -or $taskTunnelInfo.ExecutablePath -ne (Join-Path $PSScriptRoot 'tunnel\tunnel-client.exe') -or -not $taskTunnelInfo.CommandLine.Contains($taskProfilePath)) { throw 'Tunnel process ownership check failed.' }
    $taskProcesses = @([Diagnostics.Process]::GetProcessById([int]$taskGateway.pid), [Diagnostics.Process]::GetProcessById([int]$taskRuntime.process.pid))
    try {
        # Access handles immediately; a reused PID must not pass the creation-time check.
        for ($taskIndex=0; $taskIndex -lt 2; $taskIndex++) {
            $null = $taskProcesses[$taskIndex].Handle
            $taskCreation = if ($taskIndex -eq 0) { $taskGatewayInfo.CreationDate } else { $taskTunnelInfo.CreationDate }
            if ([Math]::Abs(($taskProcesses[$taskIndex].StartTime - $taskCreation).TotalSeconds) -gt 1) { throw 'Process changed while attaching supervision.' }
        }
        return $taskProcesses
    } catch { foreach ($taskProcess in $taskProcesses) { $taskProcess.Dispose() }; throw }
}
function Invoke-AssistantTunnel([string[]]$Arguments) {
    $taskRaw = & (Join-Path $PSScriptRoot 'tunnel\tunnel-client.exe') @Arguments 2>&1
    $taskExit = $LASTEXITCODE
    if ($taskExit -ne 0) { throw ('Tunnel command failed with exit ' + $taskExit + '. Check connection, credential and private runtime logs locally.') }
    try { ($taskRaw -join "`n") | ConvertFrom-Json }
    catch { throw 'Tunnel command returned unexpected output. Check the installed CLI version locally.' }
}
function Get-AssistantGateway {
    $taskFile = Join-Path $PSScriptRoot 'gateway.state.private.json'
    if (-not (Test-Path -LiteralPath $taskFile)) { return $null }
    try {
        $taskGateway = Get-Content -LiteralPath $taskFile -Raw | ConvertFrom-Json
        if ($taskGateway.base -notmatch '^http://127\.0\.0\.1:\d+$') { return $null }
        $taskHealth = Invoke-RestMethod -Uri ($taskGateway.base + '/health') -TimeoutSec 3
        if ($taskHealth.instance -eq $taskGateway.instance -and $taskHealth.version -in @('1.1.0','1.2.0-local','1.2.1-local') -and $taskHealth.healthy) { return $taskGateway }
    } catch { return $null }
    return $null
}
function Get-AssistantTunnelBinding($Runtime, $Gateway) {
    # The CLI's profile and process.target_value are desired state. A reused
    # daemon can still have the old URL in memory: inspect the live admin API.
    $taskResult = @{matches=$false;reason='not_observed';actualUrl=''}
    if (-not $Runtime.process_running -or -not $Gateway) { $taskResult.reason='process_unavailable'; return $taskResult }
    try {
        if ($Runtime.health_url -notmatch '^http://127\.0\.0\.1:\d+/healthz$') { throw 'Invalid local admin address.' }
        $taskInfo = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$Runtime.process.pid)
        if (-not $taskInfo -or $taskInfo.ExecutablePath -ne (Join-Path $PSScriptRoot 'tunnel\tunnel-client.exe') -or -not $taskInfo.CommandLine.Contains((Join-Path $PSScriptRoot 'profiles'))) { throw 'Runtime ownership mismatch.' }
        $taskAdminUrl = ([uri]$Runtime.health_url).GetLeftPart([UriPartial]::Authority)
        $taskLive = Invoke-RestMethod -Uri ($taskAdminUrl + '/api/status') -TimeoutSec 5
        if ([Math]::Abs(([datetime]$taskLive.started_at - $taskInfo.CreationDate).TotalSeconds) -gt 2) { throw 'Admin process identity mismatch.' }
        $taskResult.actualUrl = [string]$taskLive.mcp_server_url
        $taskResult.matches = $taskResult.actualUrl -eq $Gateway.mcpUrl
        $taskResult.reason = if ($taskResult.matches) { 'live_target_matches' } else { 'live_target_mismatch' }
    } catch { $taskResult.reason='live_target_unavailable' }
    return $taskResult
}
