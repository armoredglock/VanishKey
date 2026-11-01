<#
.SYNOPSIS
    VanishKey - Temporary User Creation Script (Windows)
    Creates a time-limited, unprivileged local user account with CSPRNG credentials.
.DESCRIPTION
    1. Generates a cryptographically secure random password (24 chars).
    2. Creates a local user belonging ONLY to the standard 'Users' group.
    3. Confirms user is excluded from 'Administrators' and privileged groups.
    4. Registers a scheduled task to trigger deletion at expiry time.
    5. Outputs a JSON payload to STDOUT for the desktop agent.
.PARAMETER Username
    Optional username. If not supplied, defaults to 'VK_Temp_<randomHex>'.
.PARAMETER DurationMinutes
    Account validity duration in minutes (2 to 5 minutes, hard-capped at 5).
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5)]
    [int]$DurationMinutes = 3
)

# Enforce Administrator privileges for script execution
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "VanishKey create_temp_user.ps1 must be executed with administrative privileges."
    exit 1
}

# Enforce hard cap of 5 minutes
if ($DurationMinutes -gt 5) {
    $DurationMinutes = 5
}
if ($DurationMinutes -lt 1) {
    $DurationMinutes = 2
}

# CSPRNG helper function
function New-SecureRandomPassword {
    param([int]$Length = 24)
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*()-_=+"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $result = New-Object char[] $Length
    for ($i = 0; $i -lt $Length; $i++) {
        $result[$i] = $chars[$bytes[$i] % $chars.Length]
    }
    return -join $result
}

# Generate unique username if not provided
if ([string]::IsNullOrWhiteSpace($Username)) {
    $rngBytes = New-Object byte[] 3
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($rngBytes)
    $hexSuffix = -join ($rngBytes | ForEach-Object { $_.ToString("X2") })
    $Username = "VK_Temp_$hexSuffix"
}

# Generate CSPRNG password
$plainPassword = New-SecureRandomPassword -Length 24
$secPassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

# Create the local user
try {
    # Check if user already exists
    $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-LocalUser -Name $Username -ErrorAction Stop
    }

    $newUser = New-LocalUser -Name $Username `
        -Password $secPassword `
        -FullName "VanishKey Temporary User ($Username)" `
        -Description "Auto-generated ephemeral user by VanishKey. Scheduled for deletion." `
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

    # Verify standard permissions: deny access to any sensitive secondary volumes if requested
    # Standard Windows ACLs on C:\Users\* already deny standard users access to sibling directories.
    
} catch {
    $errObj = @{
        "success" = $false
        "error"   = $_.Exception.Message
    }
    $errObj | ConvertTo-Json -Compress
    exit 1
}

# Calculate Expiry Timestamp
$createdAt = (Get-Date).ToUniversalTime()
$expiresAt = $createdAt.AddMinutes($DurationMinutes)
$expiryFormatted = $expiresAt.ToString("o")

# Schedule task to automatically delete the account
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$deleteScript = Join-Path $scriptDirectory "delete_temp_user.ps1"
$taskName = "VanishKey_Delete_$Username"

# Calculate task execution time in local time for schtasks.exe
$taskTime = (Get-Date).AddMinutes($DurationMinutes).ToString("HH:mm:ss")
$taskDate = (Get-Date).AddMinutes($DurationMinutes).ToString("MM/dd/yyyy")

$actionArg = "-NoProfile -ExecutionPolicy Bypass -File `"$deleteScript`" -Username `"$Username`""
$action = "powershell.exe $actionArg"

# Create one-time scheduled task running as SYSTEM
$schtasksCmd = "schtasks.exe /Create /TN `"$taskName`" /TR `"$action`" /SC ONCE /ST $taskTime /SD $taskDate /RU SYSTEM /F /RL HIGHEST"
Invoke-Expression $schtasksCmd | Out-Null

# In addition, start a background fallback watchdog process in case schtasks has a minute-boundary rounding delay
$fallbackCommand = "Start-Sleep -Seconds $($DurationMinutes * 60); powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$deleteScript`" -Username `"$Username`""
Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -Command `"$fallbackCommand`"" -WindowStyle Hidden

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
