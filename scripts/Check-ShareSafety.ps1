param([string]$PackageDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\','/')
$taskRules = [ordered]@{
    secret = '(?i)\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b'
    github_secret = '(?i)\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'
    account_id = '(?i)\b(?:tunnel_|org-|user-|proj_|link_|plugin_asdk_app_|plugin_connector_|asdk_app_|asdk_app_v_)[A-Za-z0-9_-]{16,}\b'
    uuid_identifier = '(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b'
    private_chat = 'https://chatgpt\.com/(?:c|g)/[a-f0-9-]{20,}'
    personal_path = '(?i)[A-Z]:[\\/]+Users[\\/]+(?!Public(?:[\\/]|$)|Default(?:[\\/]|$))[^\\/\s"<>]+'
}
$taskFindings = @()
$taskFiles = @(Get-ChildItem -LiteralPath $taskRoot -Recurse -File -Force)
foreach ($taskFile in $taskFiles) {
    $taskRelative = $taskFile.FullName.Substring($taskRoot.Length + 1)
    if ($taskRelative -match '^\.git([\\/]|$)') { continue }
    if ($taskRelative -match '(?i)(^|[\\/])(credentials|node_modules|profiles|test-data)([\\/]|$)|local-settings-backup\.json$|\.dpapi$|\.private\.|\.log$|\.(exe|dll|pdf|docx|xlsx)$') {
        $taskFindings += [pscustomobject]@{file=$taskRelative;rule='private_or_binary_artifact'}
    }
    $taskContent = [IO.File]::ReadAllText($taskFile.FullName)
    foreach ($taskRule in $taskRules.GetEnumerator()) {
        if ([regex]::IsMatch($taskContent,$taskRule.Value)) { $taskFindings += [pscustomobject]@{file=$taskRelative;rule=$taskRule.Key} }
    }
}
[pscustomobject]@{shareSafe=($taskFindings.Count -eq 0);fileCount=@($taskFiles | Where-Object { $_.FullName.Substring($taskRoot.Length + 1) -notmatch '^\.git([\\/]|$)' }).Count;findings=$taskFindings} | ConvertTo-Json -Depth 5
if ($taskFindings.Count -gt 0) { throw 'Public package contains prohibited data or artifacts. Values are intentionally not printed.' }
