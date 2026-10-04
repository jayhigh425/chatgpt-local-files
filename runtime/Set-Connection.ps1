param([Parameter(Mandatory=$true)][string]$TunnelId)
. (Join-Path $PSScriptRoot 'Common.ps1')
if ($TunnelId -notmatch '^tunnel_[a-zA-Z0-9_-]{8,128}$') { throw 'Enter your own tunnel ID from the Platform tunnel page.' }
$taskSettings = Get-AssistantSettings
$taskSettings.tunnelId = $TunnelId.Trim()
Save-AssistantSettings $taskSettings
Write-Output 'Your tunnel ID was saved in the private runtime directory.'
