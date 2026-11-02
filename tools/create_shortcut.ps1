$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "VanishKey Host.lnk"
$sc = $ws.CreateShortcut($lnkPath)
$sc.TargetPath = "D:\PROJECTS\VanishKey\Launch-VanishKey-Host.bat"
$sc.WorkingDirectory = "D:\PROJECTS\VanishKey"
$sc.Description = "Launch VanishKey Host as Administrator"
$sc.Save()

$bytes = [System.IO.File]::ReadAllBytes($lnkPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($lnkPath, $bytes)
Write-Output "Shortcut created successfully at $lnkPath"
