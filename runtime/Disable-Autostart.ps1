. (Join-Path $PSScriptRoot 'Common.ps1')
$taskShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'ChatGPT Local Assistant.lnk'
if (Test-Path -LiteralPath $taskShortcut) { Remove-Item -LiteralPath $taskShortcut }
$taskSettings = Get-AssistantSettings
$taskSettings.autostart = $false
Save-AssistantSettings $taskSettings
Write-Output 'Current-user startup shortcut removed. Runtime files were preserved.'
