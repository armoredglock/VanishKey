Add-Type -AssemblyName System.Drawing

$srcPath = "C:\Users\User\.gemini\antigravity\brain\1e9fb27a-e75f-4047-a4df-a048a004f7ba\vanishkey_app_icon_1793553171966.jpg"
$srcImg = [System.Drawing.Image]::FromFile($srcPath)

function Save-Resized([int]$width, [int]$height, [string]$destPath) {
    $dir = Split-Path $destPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($srcImg, 0, 0, $width, $height)
    $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Host "Created: $destPath ($width x $height)"
}

Save-Resized 48 48 "D:\PROJECTS\VanishKey\mobile_app\android\app\src\main\res\mipmap-mdpi\ic_launcher.png"
Save-Resized 72 72 "D:\PROJECTS\VanishKey\mobile_app\android\app\src\main\res\mipmap-hdpi\ic_launcher.png"
Save-Resized 96 96 "D:\PROJECTS\VanishKey\mobile_app\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png"
Save-Resized 144 144 "D:\PROJECTS\VanishKey\mobile_app\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png"
Save-Resized 192 192 "D:\PROJECTS\VanishKey\mobile_app\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"
Save-Resized 512 512 "D:\PROJECTS\VanishKey\mobile_app\assets\icon\app_icon.png"
Save-Resized 64 64 "D:\PROJECTS\VanishKey\desktop_agent\assets\tray_icon.png"

$srcImg.Dispose()
Write-Host "All icons generated successfully!"
