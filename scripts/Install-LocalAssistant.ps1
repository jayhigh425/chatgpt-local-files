[CmdletBinding()]
param(
    [string]$RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'ChatGPTLocalAssistant'),
    [ValidateSet('Restricted','Full')][string]$AccessMode = 'Restricted',
    [string[]]$AllowedDirectories = @(),
    [string]$NodeExecutable,
    [string]$TunnelArchivePath,
    [string]$ConfigHome
)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitOperatingSystem) { throw 'This installer requires 64-bit Windows.' }
$taskKit = Split-Path $PSScriptRoot -Parent
$taskRuntime = [IO.Path]::GetFullPath($RuntimeDirectory)
$taskKitRoot = [IO.Path]::GetFullPath($taskKit).TrimEnd('\')
if ($taskRuntime.TrimEnd('\').Equals($taskKitRoot, [StringComparison]::OrdinalIgnoreCase) -or $taskRuntime.StartsWith($taskKitRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install into a private directory outside the public kit.' }
$taskOwnedProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'node.exe' -and $_.CommandLine -and $_.CommandLine.Contains((Join-Path $taskRuntime 'task-gateway.mjs'))) -or
    ($_.ExecutablePath -eq (Join-Path $taskRuntime 'assets\keeper-host.exe')) -or
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -and ($_.CommandLine.Contains((Join-Path $taskRuntime 'KeepAlive-LocalAssistant.ps1')) -or $_.CommandLine.Contains((Join-Path $taskRuntime 'Supervise-LocalAssistant.ps1'))))
})
if ($taskOwnedProcesses.Count) { throw 'This installation is still running. Finish its tasks, stop it and disable its supervision before upgrading; see docs/UPGRADING.md.' }
$taskSettingsPath = Join-Path $taskRuntime 'settings.private.json'
$taskPrevious = if (Test-Path -LiteralPath $taskSettingsPath) { Get-Content -LiteralPath $taskSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
if ($taskPrevious) {
    if (-not $PSBoundParameters.ContainsKey('AccessMode')) { $AccessMode = $taskPrevious.accessMode }
    if (-not $PSBoundParameters.ContainsKey('AllowedDirectories')) { $AllowedDirectories = @($taskPrevious.allowedDirectories) }
    if (-not $PSBoundParameters.ContainsKey('ConfigHome')) { $ConfigHome = $taskPrevious.configHome }
}
$taskDownloads = Get-Content -LiteralPath (Join-Path $taskKit 'assets\downloads.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $taskRuntime -Force | Out-Null
$taskCache = Join-Path $taskRuntime 'downloads'
New-Item -ItemType Directory -Path $taskCache -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $NodeExecutable) {
    $taskCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($taskCommand) { $NodeExecutable = $taskCommand.Source }
}
$taskNodeWorks = $false
if ($NodeExecutable -and (Test-Path -LiteralPath $NodeExecutable -PathType Leaf)) {
    $taskNodeVersion = & $NodeExecutable --version
    if ($LASTEXITCODE -eq 0 -and $taskNodeVersion -match '^v(\d+)\.' -and [int]$Matches[1] -ge 22) { $taskNodeWorks = $true }
}
if (-not $taskNodeWorks) {
    Write-Output 'Downloading a verified portable Node.js 22 runtime from nodejs.org.'
    $taskManifest = (Invoke-WebRequest -UseBasicParsing -Uri $taskDownloads.nodeManifestUrl).Content
    $taskNodeLine = [regex]::Match($taskManifest, '(?m)^([0-9a-f]{64})\s+(node-v22\.[0-9.]+-win-x64\.zip)\s*$')
    if (-not $taskNodeLine.Success) { throw 'Official Node.js manifest did not contain the expected Windows x64 archive.' }
    $taskNodeZip = Join-Path $taskCache $taskNodeLine.Groups[2].Value
    $taskNodeUrl = 'https://nodejs.org/dist/latest-v22.x/' + $taskNodeLine.Groups[2].Value
    Invoke-WebRequest -UseBasicParsing -Uri $taskNodeUrl -OutFile $taskNodeZip
    if ((Get-FileHash -LiteralPath $taskNodeZip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskNodeLine.Groups[1].Value) { throw 'Node.js archive SHA256 mismatch.' }
    Expand-Archive -LiteralPath $taskNodeZip -DestinationPath (Join-Path $taskRuntime 'node') -Force
    $NodeExecutable = Join-Path (Join-Path $taskRuntime 'node') ($taskNodeLine.Groups[2].Value.Replace('.zip','') + '\node.exe')
}
$NodeExecutable = [IO.Path]::GetFullPath($NodeExecutable)
$taskNpm = Join-Path (Split-Path $NodeExecutable -Parent) 'npm.cmd'
if (-not (Test-Path -LiteralPath $taskNpm -PathType Leaf)) { throw 'npm.cmd was not found beside the selected Node.js executable.' }

if (-not $TunnelArchivePath) {
    $TunnelArchivePath = Join-Path $taskCache 'tunnel-client-windows-amd64.zip'
    if (-not (Test-Path -LiteralPath $TunnelArchivePath)) { Invoke-WebRequest -UseBasicParsing -Uri $taskDownloads.tunnelUrl -OutFile $TunnelArchivePath }
}
if ((Get-FileHash -LiteralPath $TunnelArchivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskDownloads.tunnelSha256) { throw 'Tunnel archive SHA256 mismatch; do not use this download.' }
Expand-Archive -LiteralPath $TunnelArchivePath -DestinationPath (Join-Path $taskRuntime 'tunnel') -Force
if (-not (Test-Path -LiteralPath (Join-Path $taskRuntime 'tunnel\tunnel-client.exe'))) { throw 'Expected tunnel-client.exe is missing from the verified archive.' }

Copy-Item -LiteralPath (Join-Path $taskKit 'assets\package.json') -Destination (Join-Path $taskRuntime 'package.json') -Force
Copy-Item -LiteralPath (Join-Path $taskKit 'assets\package-lock.json') -Destination (Join-Path $taskRuntime 'package-lock.json') -Force
Get-ChildItem -LiteralPath (Join-Path $taskKit 'runtime') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $taskRuntime -Force }
& (Join-Path $taskRuntime 'Build-KeeperHost.ps1')
$taskOldPath = $env:PATH
$taskOldPuppeteer = $env:PUPPETEER_SKIP_DOWNLOAD
$taskOldTrack = $env:DO_NOT_TRACK
try {
    $env:PATH = (Split-Path $NodeExecutable -Parent) + ';' + $taskOldPath
    $env:PUPPETEER_SKIP_DOWNLOAD = 'true'
    $env:DO_NOT_TRACK = '1'
    Push-Location -LiteralPath $taskRuntime
    try { & $taskNpm ci --no-fund --no-audit; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' } }
    finally { Pop-Location }
} finally {
    $env:PATH = $taskOldPath
    $env:PUPPETEER_SKIP_DOWNLOAD = $taskOldPuppeteer
    $env:DO_NOT_TRACK = $taskOldTrack
}

if ($AccessMode -eq 'Restricted' -and $AllowedDirectories.Count -eq 0) { $AllowedDirectories = @(Join-Path $taskRuntime 'sandbox') }
if ($AccessMode -eq 'Restricted') {
    $AllowedDirectories = @($AllowedDirectories | ForEach-Object { [IO.Path]::GetFullPath($_) })
    foreach ($taskDir in $AllowedDirectories) { if (-not (Test-Path -LiteralPath $taskDir -PathType Container)) { New-Item -ItemType Directory -Path $taskDir -Force | Out-Null } }
} else { $AllowedDirectories = @() }
$taskSettings = [ordered]@{
    schemaVersion = 2; pluginName = '本地电脑助手'; alias = 'chatgpt-local-assistant';
    accessMode = $AccessMode; allowedDirectories = @($AllowedDirectories);
    nodeExecutable = $NodeExecutable; tunnelId = ''; configHome = ''; autostart = $false
}
if ($taskPrevious) { $taskSettings.tunnelId = $taskPrevious.tunnelId; $taskSettings.autostart = $taskPrevious.autostart }
if ($ConfigHome) { $taskSettings.configHome = [IO.Path]::GetFullPath($ConfigHome); New-Item -ItemType Directory -Path $taskSettings.configHome -Force | Out-Null }
$taskSettings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $taskSettingsPath -Encoding UTF8
& $NodeExecutable (Join-Path $taskRuntime 'configure-local.mjs') $taskSettingsPath
if ($LASTEXITCODE -ne 0) { throw 'Local MCP configuration or verification failed.' }
& $NodeExecutable (Join-Path $taskRuntime 'prepare-concurrency.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Task gateway preparation failed.' }
Write-Output ('Local stage complete. Private runtime: ' + $taskRuntime)
Write-Output 'Continue with your own account, tunnel, credential and ordinary Chat verification. ChatGPT setup is not complete yet.'
