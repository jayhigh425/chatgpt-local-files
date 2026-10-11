. (Join-Path $PSScriptRoot 'Common.ps1')
$taskGateway = Get-AssistantGateway
if (-not $taskGateway) {
    & (Join-Path $PSScriptRoot 'Start-LocalFiles.ps1') | Out-Null
    $taskGateway = Get-AssistantGateway
}
if (-not $taskGateway) { throw 'Local gateway could not start. Run Status-LocalFiles.ps1 for diagnostics.' }
Start-Process -FilePath ($taskGateway.base + '/ui') -WindowStyle Hidden
