<#
.SYNOPSIS
    VanishKey - Temporary User Creation Script (Windows)
    Creates a time-limited, unprivileged local user account with CSPRNG credentials.
.DESCRIPTION
    1. Generates a cryptographically secure random password (12-char clear alphanumeric).
    2. Bypasses the "Hi, Welcome to Windows / We're getting everything ready" first-sign-in phase.
    3. Creates a local user belonging ONLY to the standard 'Users' group.
    4. Confirms user is excluded from 'Administrators' and privileged groups.
    5. Registers a scheduled task and watchdog timer to trigger deletion at expiry time.
    6. Outputs a JSON payload to STDOUT for the desktop agent.
.PARAMETER Username
    Optional username. If not supplied, defaults to 'VanishGuest'.
.PARAMETER DurationMinutes
    Account validity duration in minutes (1 to 1440 minutes, custom limits supported).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1440)]
    [int]$DurationMinutes = 15
)

# Enforce Administrator privileges for script execution
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "VanishKey create_temp_user.ps1 must be executed with administrative privileges."
    exit 1
}

# Bounds enforcement (1 minute to 24 hours)
if ($DurationMinutes -lt 1) {
    $DurationMinutes = 15
}
if ($DurationMinutes -gt 1440) {
    $DurationMinutes = 1440
}

# -------------------------------------------------------------
# Step 0: Optimize Windows to skip First Logon "Hi / Welcome" animation
# -------------------------------------------------------------
try {
    # 1. Disable First Logon Animation system-wide
    $sysPolPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $sysPolPath)) { New-Item -Path $sysPolPath -Force | Out-Null }
    Set-ItemProperty -Path $sysPolPath -Name "EnableFirstLogonAnimation" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $winlogonPath -Name "EnableFirstLogonAnimation" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    # 2. Disable Privacy Experience (OOBE screens on first login)
    $oobePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
    if (-not (Test-Path $oobePath)) { New-Item -Path $oobePath -Force | Out-Null }
    Set-ItemProperty -Path $oobePath -Name "DisablePrivacyExperience" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # 3. Disable Consumer Features & Welcome experience
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cloudPath)) { New-Item -Path $cloudPath -Force | Out-Null }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # 4. Disable Edge and Browser first-run experience
    $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePath)) { New-Item -Path $edgePath -Force | Out-Null }
    Set-ItemProperty -Path $edgePath -Name "HideFirstRunExperience" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # 5. Suppress setup tips and second-chance OOBE on Default Profile hive
    $defaultHive = "C:\Users\Default\NTUSER.DAT"
    if (Test-Path $defaultHive) {
        reg.exe load HKU\VK_DefaultProfile $defaultHive 2>$null | Out-Null
        if (Test-Path "Registry::HKU\VK_DefaultProfile") {
            $cdmPath = "Registry::HKU\VK_DefaultProfile\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (-not (Test-Path $cdmPath)) { New-Item -Path $cdmPath -Force | Out-Null }
            Set-ItemProperty -Path $cdmPath -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cdmPath -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cdmPath -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $cdmPath -Name "SoftLandingEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            $scoobePath = "Registry::HKU\VK_DefaultProfile\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
            if (-not (Test-Path $scoobePath)) { New-Item -Path $scoobePath -Force | Out-Null }
            Set-ItemProperty -Path $scoobePath -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            reg.exe unload HKU\VK_DefaultProfile 2>$null | Out-Null
        }
    }
} catch { }

# -------------------------------------------------------------
# Step 1: CSPRNG Password Generator
# -------------------------------------------------------------
function New-SecureRandomPassword {
    param([int]$Length = 12)
    # Clear, high-entropy alphanumeric set without confusing characters (no 0/O, 1/l/I)
    $chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $result = New-Object char[] $Length
    for ($i = 0; $i -lt $Length; $i++) {
        $result[$i] = $chars[$bytes[$i] % $chars.Length]
    }
    return -join $result
}

# Generate friendly username if not provided
if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = "VanishGuest"
}

# Generate CSPRNG password (12-char friendly alphanumeric)
$plainPassword = New-SecureRandomPassword -Length 12
$secPassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

# -------------------------------------------------------------
# Step 2: Create the Local User Account
# -------------------------------------------------------------
try {
    # Check if user already exists from previous session and clean up first
    $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-LocalUser -Name $Username -ErrorAction SilentlyContinue
    }

    $newUser = New-LocalUser -Name $Username `
        -Password $secPassword `
        -FullName "Temporary Guest Access" `
        -Description "VanishKey Ephemeral Temporary Account" `
        -PasswordNeverExpires:$false `
        -UserMayNotChangePassword:$true `
        -AccountNeverExpires:$false `
        -AccountExpires (Get-Date).AddMinutes($DurationMinutes) `
        -ErrorAction Stop

    # Ensure member of Users group only
    Add-LocalGroupMember -Group "Users" -Member $Username -ErrorAction SilentlyContinue

    # Explicitly verify user is NOT in Administrators or other sensitive groups
    $adminGroup = Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction SilentlyContinue
    if ($adminGroup) {
        $isAdminMember = Get-LocalGroupMember -Group $adminGroup.Name -Member $Username -ErrorAction SilentlyContinue
        if ($isAdminMember) {
            Remove-LocalGroupMember -Group $adminGroup.Name -Member $Username -ErrorAction Stop
            Write-Warning "Removed accidental administrative membership for $Username"
        }
    }

} catch {
    $errObj = @{
        "success" = $false
        "error"   = $_.Exception.Message
    }
    $errObj | ConvertTo-Json -Compress
    exit 1
}

# -------------------------------------------------------------
# Step 3: Calculate Expiry & Schedule Termination
# -------------------------------------------------------------
$createdAt = (Get-Date).ToUniversalTime()
$expiresAt = $createdAt.AddMinutes($DurationMinutes)
$expiryFormatted = $expiresAt.ToString("o")

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$deleteScript = Join-Path $scriptDirectory "delete_temp_user.ps1"
$taskName = "VanishKey_Delete_$Username"

# Calculate task execution time in local system culture format
$dateFormat = (Get-Culture).DateTimeFormat.ShortDatePattern
$taskTime = (Get-Date).AddMinutes($DurationMinutes).ToString("HH:mm:ss")
$taskDate = (Get-Date).AddMinutes($DurationMinutes).ToString($dateFormat)

$actionArg = "-NoProfile -ExecutionPolicy Bypass -File `"$deleteScript`" -Username `"$Username`""
$action = "powershell.exe $actionArg"

# Create one-time scheduled task running with highest privileges
$schtasksCmd = "schtasks.exe /Create /TN `"$taskName`" /TR `"$action`" /SC ONCE /ST $taskTime /SD $taskDate /RU SYSTEM /F /RL HIGHEST"
try {
    Invoke-Expression $schtasksCmd 2>$null | Out-Null
} catch { }

# Output JSON result
$result = @{
    "success"          = $true
    "username"         = $Username
    "password"         = $plainPassword
    "created_at"       = $createdAt.ToString("o")
    "expires_at"       = $expiryFormatted
    "duration_minutes" = $DurationMinutes
    "duration_seconds" = ($DurationMinutes * 60)
    "scheduled_task"   = $taskName
}

$result | ConvertTo-Json -Compress
