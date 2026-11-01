<#
.SYNOPSIS
    VanishKey - Temporary User Cleanup Script (Windows)
    Terminates active sessions, deletes local account, profile registry entries, and folder.
.DESCRIPTION
    1. Forcefully logs off any active sessions for the specified user.
    2. Deletes the scheduled task created for automatic cleanup.
    3. Removes the Windows User Profile via WMI (cleans up NTUSER.DAT and Registry).
    4. Removes the local user account from SAM.
    5. Verifies and removes any residual home directory under C:\Users.
    6. Outputs a JSON status report.
.PARAMETER Username
    The name of the temporary user to purge.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Username
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "VanishKey delete_temp_user.ps1 must be executed with administrative privileges."
    exit 1
}

# Safety check: Prevent accidental deletion of protected system accounts or common admin accounts
$protectedUsers = @("Administrator", "Guest", "DefaultAccount", "WDAGUtilityAccount", $env:USERNAME)
if ($protectedUsers -contains $Username) {
    $err = @{ "success" = $false; "error" = "Refusing to delete protected or current user: $Username" }
    $err | ConvertTo-Json -Compress
    exit 1
}

$cleanupReport = @{
    "username"        = $Username
    "timestamp"       = (Get-Date).ToUniversalTime().ToString("o")
    "sessions_killed" = 0
    "profile_deleted" = $false
    "user_deleted"    = $false
    "folder_deleted"  = $false
}

try {
    # 1. Terminate active sessions for the user if any exist
    try {
        $quserOutput = quser 2>$null
        if ($quserOutput) {
            foreach ($line in $quserOutput) {
                if ($line -match "^\s*>?\s*($Username)\s+(\S+)?\s+(\d+)\s+") {
                    $sessionId = $Matches[3]
                    logoff.exe $sessionId 2>$null
                    $cleanupReport.sessions_killed++
                }
            }
        }
    } catch {
        # quser/logoff might not be available or fail if user has no session
    }

    # Also terminate any processes owned by the user
    try {
        $userProcesses = Get-CimInstance Win32_Process | Where-Object {
            $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
            $owner.User -eq $Username
        }
        foreach ($proc in $userProcesses) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    # 2. Delete the scheduled task if it exists
    $taskName = "VanishKey_Delete_$Username"
    try {
        schtasks.exe /Delete /TN "$taskName" /F 2>$null | Out-Null
    } catch { }

    # 3. Clean up the Windows User Profile via CIM/WMI
    try {
        $profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {
            $_.LocalPath -like "*\$Username" -or $_.LocalPath -like "*\$Username.*"
        }
        foreach ($prof in $profiles) {
            Remove-CimInstance -InputObject $prof -ErrorAction SilentlyContinue
            $cleanupReport.profile_deleted = $true
        }
    } catch { }

    # 4. Remove the local user account
    $localUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($localUser) {
        Remove-LocalUser -Name $Username -ErrorAction Stop
        $cleanupReport.user_deleted = $true
    } else {
        # In case it was already deleted
        $cleanupReport.user_deleted = $true
    }

    # 5. Clean up any lingering folder on disk (C:\Users\<Username>)
    $userHomePath = Join-Path "C:\Users" $Username
    if (Test-Path $userHomePath) {
        # Take ownership if needed and delete
        try {
            takeown.exe /F "$userHomePath" /R /D Y 2>$null | Out-Null
            icacls.exe "$userHomePath" /grant "${env:USERNAME}:(F)" /T /C /Q 2>$null | Out-Null
            Remove-Item -Path $userHomePath -Recurse -Force -ErrorAction SilentlyContinue
        } catch { }
        $cleanupReport.folder_deleted = (-not (Test-Path $userHomePath))
    } else {
        $cleanupReport.folder_deleted = $true
    }

    $cleanupReport["success"] = $true
    $cleanupReport | ConvertTo-Json -Compress
    exit 0

} catch {
    $errObj = @{
        "success" = $false
        "error"   = $_.Exception.Message
        "report"  = $cleanupReport
    }
    $errObj | ConvertTo-Json -Compress
    exit 1
}
