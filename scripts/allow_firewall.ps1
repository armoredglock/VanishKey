Set-NetConnectionProfile -InterfaceAlias 'Wi-Fi' -NetworkCategory Private -ErrorAction SilentlyContinue
netsh advfirewall firewall delete rule name="VanishKey-8080"
netsh advfirewall firewall add rule name="VanishKey-8080" dir=in action=allow protocol=TCP localport=8080 profile=any
Write-Host "VanishKey Firewall Configuration Applied Successfully!" -ForegroundColor Green
Start-Sleep -Seconds 2
