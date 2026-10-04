. (Join-Path $PSScriptRoot 'Common.ps1')
$taskSettings = Get-AssistantSettings
$taskTestRoot = if ($taskSettings.accessMode -eq 'Full') { Join-Path $PSScriptRoot 'sandbox' } else { $taskSettings.allowedDirectories[0] }
$taskDir = Join-Path $taskTestRoot ('chat-acceptance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
$taskNonce = [guid]::NewGuid().ToString('N')
$taskFixture = Join-Path $taskDir 'fixture.json'
$taskEdit = Join-Path $taskDir 'edit-test.txt'
$taskResult = Join-Path $taskDir 'result.json'
[pscustomobject]@{nonce=$taskNonce;amounts=@(17,23,31)} | ConvertTo-Json | Set-Content -LiteralPath $taskFixture -Encoding UTF8
Set-Content -LiteralPath $taskEdit -Value 'STATUS=original' -Encoding UTF8
[pscustomobject]@{testDirectory=$taskDir;fixture=$taskFixture;edit=$taskEdit;result=$taskResult} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'chat-test.private.json') -Encoding UTF8
$taskPrompt = '请在普通 Chat 模式使用“本地电脑助手”做接入验收。先调用 begin_task 创建本次独立任务，每个本地调用都携带自己的 task_id。读取 ' + $taskFixture + '，计算 amounts 总和，将原文 nonce 和总和分别以 nonce、amounts_total 字段写入 ' + $taskResult + '；先读取 ' + $taskEdit + '，再将其中 STATUS=original 改为 STATUS=verified。再次读取两个结果确认保存后调用 end_task。只操作这三个测试文件，不调用付费模型 API。'
$taskPrompt | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'chat-test-prompt.private.txt') -Encoding UTF8
Write-Output $taskPrompt
Write-Output 'Send the prompt in ordinary Chat, then run Confirm-ChatVerification.ps1. Codex must not create the expected output itself.'
