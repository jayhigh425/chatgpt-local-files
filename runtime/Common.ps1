$ErrorActionPreference = 'Stop'
# When Windows PowerShell is launched from PowerShell 7, inherited PSModulePath
# can otherwise resolve an incompatible Security module. Use this host's module.
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
function Get-AssistantSettings {
    $taskFile = Join-Path $PSScriptRoot 'settings.private.json'
    if (-not (Test-Path -LiteralPath $taskFile)) { throw 'Run the kit installer first.' }
    Get-Content -LiteralPath $taskFile -Raw | ConvertFrom-Json
}
function Save-AssistantSettings($Settings) {
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.private.json') -Encoding UTF8
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
        if ($taskHealth.instance -eq $taskGateway.instance -and $taskHealth.version -eq '1.1.0' -and $taskHealth.healthy) { return $taskGateway }
    } catch { return $null }
    return $null
}
