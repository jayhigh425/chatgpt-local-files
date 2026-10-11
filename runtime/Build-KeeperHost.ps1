$ErrorActionPreference = 'Stop'
$taskCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $taskCompiler)) { $taskCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $taskCompiler)) { throw 'Windows .NET Framework compiler is unavailable.' }
$taskAssets = Join-Path $PSScriptRoot 'assets'
$null = New-Item -ItemType Directory -Path $taskAssets -Force
$taskHost = Join-Path $taskAssets 'keeper-host.exe'
if (Get-CimInstance Win32_Process -Filter "Name='keeper-host.exe'" | Where-Object ExecutablePath -eq $taskHost) { throw 'Stop the native guardian before rebuilding it.' }
& $taskCompiler /nologo /target:winexe /optimize+ /debug- /reference:System.Web.Extensions.dll /reference:System.Management.dll ('/out:' + $taskHost) (Join-Path $PSScriptRoot 'KeeperHost.cs')
if ($LASTEXITCODE -ne 0) { throw 'Native guardian compilation failed.' }
Write-Output 'Native no-console guardian built.'
