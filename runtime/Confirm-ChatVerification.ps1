. (Join-Path $PSScriptRoot 'Common.ps1')
$taskTestFile = Join-Path $PSScriptRoot 'chat-test.private.json'
if (-not (Test-Path -LiteralPath $taskTestFile)) { throw 'Run New-ChatVerification.ps1 first.' }
$taskTest = Get-Content -LiteralPath $taskTestFile -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $taskTest.result)) { throw 'Chat has not created the local output file yet.' }
$taskFixture = Get-Content -LiteralPath $taskTest.fixture -Raw | ConvertFrom-Json
$taskResult = Get-Content -LiteralPath $taskTest.result -Raw | ConvertFrom-Json
$taskEdit = Get-Content -LiteralPath $taskTest.edit -Raw
$taskSum = ($taskFixture.amounts | Measure-Object -Sum).Sum
$taskVerified = $taskResult.nonce -ceq $taskFixture.nonce -and $taskResult.amounts_total -eq $taskSum -and $taskEdit.Trim() -ceq 'STATUS=verified'
$taskReport = [pscustomobject]@{verified=[bool]$taskVerified;nonceMatches=($taskResult.nonce -ceq $taskFixture.nonce);sumMatches=($taskResult.amounts_total -eq $taskSum);editVerified=($taskEdit.Trim() -ceq 'STATUS=verified');at=(Get-Date).ToString('o')}
$taskReport | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'chat-verification.private.json') -Encoding UTF8
$taskReport | ConvertTo-Json
if (-not $taskVerified) { throw 'Ordinary Chat local read/write/edit acceptance is incomplete.' }
