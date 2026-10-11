. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.Drawing
$taskAssets = Join-Path $PSScriptRoot 'assets'
$null = New-Item -ItemType Directory -Path $taskAssets -Force
$taskBitmap = New-Object Drawing.Bitmap(256,256)
$taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
$taskGreen = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255,34,114,98))
$taskWhite = New-Object Drawing.SolidBrush([Drawing.Color]::White)
$taskPen = New-Object Drawing.Pen([Drawing.Color]::White,12)
$taskThinPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,210,237,225),7)
$taskMemory = New-Object IO.MemoryStream
try {
    $taskGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $taskGraphics.Clear([Drawing.Color]::Transparent)
    $taskGraphics.FillEllipse($taskGreen,4,4,248,248)
    $taskGraphics.DrawRectangle($taskPen,48,60,160,110)
    $taskGraphics.DrawLine($taskPen,128,170,128,198)
    $taskGraphics.DrawLine($taskPen,90,198,166,198)
    $taskGraphics.DrawLines($taskThinPen,[Drawing.Point[]]@([Drawing.Point]::new(66,130),[Drawing.Point]::new(93,130),[Drawing.Point]::new(111,98),[Drawing.Point]::new(136,147),[Drawing.Point]::new(155,118),[Drawing.Point]::new(189,118)))
    $taskBitmap.Save((Join-Path $taskAssets 'status-icon.png'),[Drawing.Imaging.ImageFormat]::Png)
    $taskBitmap.Save($taskMemory,[Drawing.Imaging.ImageFormat]::Png)
    $taskPng = $taskMemory.ToArray()
    $taskIconFile = [IO.File]::Create((Join-Path $taskAssets 'status-icon.ico'))
    $taskWriter = New-Object IO.BinaryWriter($taskIconFile)
    try {
        $taskWriter.Write([uint16]0); $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]1)
        $taskWriter.Write([byte]0); $taskWriter.Write([byte]0); $taskWriter.Write([byte]0); $taskWriter.Write([byte]0)
        $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]32); $taskWriter.Write([uint32]$taskPng.Length); $taskWriter.Write([uint32]22)
        $taskWriter.Write($taskPng)
    } finally { $taskWriter.Dispose(); $taskIconFile.Dispose() }
} finally { $taskMemory.Dispose(); $taskPen.Dispose(); $taskThinPen.Dispose(); $taskWhite.Dispose(); $taskGreen.Dispose(); $taskGraphics.Dispose(); $taskBitmap.Dispose() }
$taskShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '本地电脑助手状态.lnk'
$taskShell = New-Object -ComObject WScript.Shell
$taskLink = $taskShell.CreateShortcut($taskShortcut)
if ((Test-Path -LiteralPath $taskShortcut) -and -not $taskLink.Arguments.Contains($PSScriptRoot)) { throw 'Existing desktop shortcut belongs to another application.' }
$taskLink.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$taskLink.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Open-Status.ps1') + '"'
$taskLink.WorkingDirectory = $PSScriptRoot
$taskLink.Description = '查看本地电脑助手连接、守护和后台任务状态'
$taskLink.IconLocation = (Join-Path $taskAssets 'status-icon.ico') + ',0'
$taskLink.WindowStyle = 7
$taskLink.Save()
[pscustomobject]@{shortcut=$taskShortcut;icon=$taskLink.IconLocation;dynamicPort=$true} | ConvertTo-Json
