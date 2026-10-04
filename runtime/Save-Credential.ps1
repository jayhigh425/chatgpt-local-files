param([Security.SecureString]$Secret, [switch]$FromClipboard)
. (Join-Path $PSScriptRoot 'Common.ps1')
if ($FromClipboard -and $Secret) { throw 'Choose SecureString input or clipboard input, not both.' }
if ($FromClipboard) {
    $taskClipboard = Get-Clipboard -Raw
    if (-not $taskClipboard -or -not $taskClipboard.Trim().StartsWith('sk-')) { throw 'The clipboard does not contain the expected newly created runtime API key.' }
    $Secret = ConvertTo-SecureString $taskClipboard.Trim() -AsPlainText -Force
    $taskClipboard = $null
}
if (-not $Secret) { $Secret = Read-Host 'Enter your own Tunnels Read/Use runtime key (hidden input)' -AsSecureString }
$taskPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
try {
    $taskPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($taskPtr)
    if (-not $taskPlain.StartsWith('sk-') -or $taskPlain.Length -lt 20) { throw 'The provided value is not a runtime API key.' }
    $taskPlain = $null
    $taskDir = Join-Path $PSScriptRoot 'credentials'
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    $taskSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $taskDir /inheritance:r /grant:r ('*' + $taskSid + ':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Credential directory ACL could not be restricted.' }
    ConvertFrom-SecureString $Secret | Set-Content -LiteralPath (Join-Path $taskDir 'tunnel-key.dpapi') -Encoding ASCII
    if ($FromClipboard) { Set-Clipboard -Value '' }
    Write-Output 'Credential encrypted with Windows DPAPI. No secret was printed.'
} finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($taskPtr); $taskPlain = $null }
