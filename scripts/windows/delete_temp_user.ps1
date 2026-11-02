<#
.SYNOPSIS
    VanishKey - Temporary User Cleanup Script (Windows)
    Terminates active sessions, deletes local account, profile registry entries, and folder.
.DESCRIPTION
    1. Only terminates sessions and locks screen IF the guest user is actually logged in.
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
    # -------------------------------------------------------------
    # 1. Check if Guest User is Actually Logged In / Running Processes
    # -------------------------------------------------------------
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class VanishSessionManager {
    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSLogoffSession(IntPtr hServer, int SessionId, bool bWait);
    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSDisconnectSession(IntPtr hServer, int SessionId, bool bWait);
    [DllImport("kernel32.dll")]
    public static extern uint WTSGetActiveConsoleSessionId();
}
"@ -ErrorAction SilentlyContinue

        $activeSessionId = [VanishSessionManager]::WTSGetActiveConsoleSessionId()

        $targetProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.GetOwner().User -eq $Username
        }

        # ONLY if guest processes are running do we kill processes and log off
        if ($targetProcs) {
            $cleanupReport.sessions_killed = $targetProcs.Count
            $guestSessionIds = $targetProcs.SessionId | Select-Object -Unique

            # Instantly terminate guest processes
            taskkill.exe /F /FI "USERNAME eq $Username" /T 2>$null | Out-Null

            # Log off the guest sessions
            foreach ($sId in $guestSessionIds) {
                try {
                    [VanishSessionManager]::WTSLogoffSession([IntPtr]::Zero, [int]$sId, $false)
                } catch { }
            }

            # ONLY lock workstation IF the guest was actively in control of the physical screen
            if ($guestSessionIds -contains $activeSessionId) {
                try {
                    rundll32.exe user32.dll,LockWorkStation
                } catch { }
            }
        }
    } catch { }

    # Small pause to allow OS kernel to release SAM and profile file locks
    Start-Sleep -Milliseconds 300

    # -------------------------------------------------------------
    # 2. Delete the scheduled task if it exists
    # -------------------------------------------------------------
    $taskName = "VanishKey_Delete_$Username"
    try {
        schtasks.exe /Delete /TN "$taskName" /F 2>$null | Out-Null
    } catch { }

    # -------------------------------------------------------------
    # 3. Remove the local user account from SAM
    # -------------------------------------------------------------
    try {
        net.exe user "$Username" /delete 2>$null | Out-Null
        Remove-LocalUser -Name "$Username" -ErrorAction SilentlyContinue
    } catch { }
    $cleanupReport.user_deleted = (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue))

    # -------------------------------------------------------------
    # 4. Clean up the Windows User Profile via CIM/WMI
    # -------------------------------------------------------------
    try {
        $profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {
            $_.LocalPath -like "*\$Username" -or $_.LocalPath -like "*\$Username.*"
        }
        foreach ($prof in $profiles) {
            Remove-CimInstance -InputObject $prof -ErrorAction SilentlyContinue
            $cleanupReport.profile_deleted = $true
        }
    } catch { }

    # -------------------------------------------------------------
    # 5. Clean up any lingering folder on disk (C:\Users\<Username>)
    # -------------------------------------------------------------
    $userHomePath = Join-Path "C:\Users" $Username
    if (Test-Path $userHomePath) {
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
