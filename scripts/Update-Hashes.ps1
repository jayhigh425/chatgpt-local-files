param([string]$PackageDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\','/')
$taskEntries = @(Get-ChildItem -LiteralPath $taskRoot -Recurse -File -Force | Where-Object {
    $taskRelative = $_.FullName.Substring($taskRoot.Length + 1)
    $taskRelative -notmatch '^\.git([\\/]|$)' -and $taskRelative -ne 'SHA256SUMS.txt'
} | ForEach-Object {
    $taskRelative = $_.FullName.Substring($taskRoot.Length + 1).Replace('\','/')
    [pscustomobject]@{ path=$taskRelative; hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
} | Sort-Object path)
$taskLines = @($taskEntries | ForEach-Object { $_.hash + '  ' + $_.path })
[IO.File]::WriteAllText((Join-Path $taskRoot 'SHA256SUMS.txt'),($taskLines -join "`n") + "`n",(New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{fileCount=$taskEntries.Count;manifest='SHA256SUMS.txt'} | ConvertTo-Json
