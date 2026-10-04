. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'ChatGPT Local Assistant.lnk'
$taskShell = New-Object -ComObject WScript.Shell
$taskLink = $taskShell.CreateShortcut($taskShortcut)
$taskLink.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskLink.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Start-LocalAssistant.ps1') + '"'
$taskLink.WorkingDirectory = $PSScriptRoot
$taskLink.WindowStyle = 7
$taskLink.Description = 'Connect this user local MCP assistant to ChatGPT.'
$taskLink.Save()
$taskSettings.autostart = $true
Save-AssistantSettings $taskSettings
Write-Output 'Hidden startup shortcut installed for the current Windows user.'
