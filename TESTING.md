# VanishKey Manual Testing & Security Verification Guide

This guide provides step-by-step procedures to manually verify that VanishKey's core account lifecycle mechanisms adhere to strict unprivileged security standards, enforce least-privilege disk access, and execute automatic cleanup.

---

## 1. Windows Verification (`scripts/windows/`)

### Test 1.1: Ephemeral Account Creation & Group Membership
**Objective:** Confirm that the generated user account is created with an unprivileged standard user role and has zero administrative rights.

1. Open an administrative PowerShell prompt:
   ```powershell
   cd D:\PROJECTS\VanishKey\scripts\windows
   .\create_temp_user.ps1 -DurationMinutes 2
   ```
2. Note the JSON output returned on STDOUT:
   ```json
   {"success":true,"username":"VK_Temp_A1B2C3","password":"...","expires_at":"...","duration_minutes":2,"scheduled_task":"VanishKey_Delete_VK_Temp_A1B2C3"}
   ```
3. Inspect the user's group memberships:
   ```powershell
   $testUser = "VK_Temp_A1B2C3" # Replace with your generated username
   Get-LocalGroup | Where-Object { (Get-LocalGroupMember $_.Name -Member $testUser -ErrorAction SilentlyContinue) } | Select-Object Name
   ```
   **Pass Criteria:**
   - The user must ONLY appear under the `Users` group.
   - The user must **never** appear under `Administrators`, `Remote Desktop Users`, `Power Users`, or `Backup Operators`.

4. Confirm with Windows `net user`:
   ```powershell
   net user $testUser
   ```
   Verify that `Local Group Memberships` shows `*Users` only.

---

### Test 1.2: Cross-Directory & Drive Isolation
**Objective:** Confirm that the temporary user cannot access other users' home directories or sensitive volume roots.

1. Test using PowerShell RunAs / impersonation or log into the temporary account:
   ```powershell
   # Start a PowerShell process as the temporary user:
   $cred = Get-Credential -UserName $testUser -Message "Enter the generated CSPRNG password"
   Start-Process powershell.exe -Credential $cred -ArgumentList "-NoExit -Command `"Write-Host Current User: `$env:USERNAME`""
   ```
2. From the new temporary user PowerShell session, attempt to read the owner's profile directory:
   ```powershell
   # Replace with the actual primary user directory
   Get-ChildItem -Path "C:\Users\User"
   ```
   **Expected Result:**
   ```
   Get-ChildItem : Access to the path 'C:\Users\User' is denied.
   ```
3. Attempt to read other private drives or sensitive system locations:
   ```powershell
   Get-ChildItem -Path "C:\Windows\System32\config"
   ```
   **Expected Result:** Access is denied.

---

### Test 1.3: Timed Deletion and Complete Cleanup
**Objective:** Confirm that after the duration expires (e.g. 2 minutes), the account, scheduled task, registry hives, and home folders are completely purged.

1. Verify that the scheduled task is registered:
   ```powershell
   schtasks.exe /Query /TN "VanishKey_Delete_$testUser"
   ```
2. Wait for the expiry duration (2 minutes).
3. Verify that the user no longer exists in SAM:
   ```powershell
   Get-LocalUser -Name $testUser
   ```
   **Expected Result:** `UserNotFoundException` or object not found.
4. Verify that the user profile directory has been completely purged:
   ```powershell
   Test-Path "C:\Users\$testUser"
   ```
   **Expected Result:** Returns `False`.
5. Verify that the profile registry hive is deleted from WMI:
   ```powershell
   Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$testUser" }
   ```
   **Expected Result:** Returns null / empty list.
6. Verify manual cleanup invocation (idempotency test):
   ```powershell
   .\delete_temp_user.ps1 -Username $testUser
   ```
   **Expected Result:** Returns `{"success":true,"status":"deleted",...}` without errors.

---

## 2. macOS Verification (`scripts/macos/`)

### Test 2.1: Ephemeral Account Creation & Privilege Verification
**Objective:** Confirm the account created via `sysadminctl` is a standard user without `sudo` or `admin` group membership.

1. Execute the creation script with root/sudo:
   ```bash
   cd scripts/macos
   sudo bash create_temp_user.sh --duration 2
   ```
2. Capture the JSON output containing `username` and `password`.
3. Verify standard group membership:
   ```bash
   id "VK_Temp_XXXXXX"
   ```
   **Pass Criteria:**
   - Group `staff` (GID 20) or standard UID (> 500).
   - Must **not** be in `admin` (GID 80) or `wheel` (GID 0).
4. Verify `sudo` denial:
   ```bash
   su - "VK_Temp_XXXXXX" -c "sudo whoami"
   ```
   **Expected Result:** `VK_Temp_XXXXXX is not in the sudoers file. This incident will be reported.`

---

### Test 2.2: Cross-Directory Isolation on macOS
**Objective:** Confirm standard POSIX permissions deny access to sibling home directories.

1. From the temporary user context:
   ```bash
   su - "VK_Temp_XXXXXX" -c "ls -la /Users/Shared"
   su - "VK_Temp_XXXXXX" -c "ls -la /Users/<primary_owner_username>"
   ```
   **Expected Result:**
   ```
   ls: /Users/<primary_owner_username>: Permission denied
   ```
2. Verify permissions on the temporary user's own home directory:
   ```bash
   ls -ld "/Users/VK_Temp_XXXXXX"
   ```
   **Expected Result:** `drwx------ (700)` owned by `VK_Temp_XXXXXX`.

---

### Test 2.3: Timed Deletion and Home Directory Cleanup
1. Verify the LaunchDaemon was scheduled:
   ```bash
   launchctl list | grep "com.vanishkey"
   ```
2. Wait 2 minutes for the timeout.
3. Check user existence:
   ```bash
   dscl . -read "/Users/VK_Temp_XXXXXX"
   ```
   **Expected Result:** `No such key: /Users/VK_Temp_XXXXXX`.
4. Check folder removal:
   ```bash
   ls -d "/Users/VK_Temp_XXXXXX"
   ```
   **Expected Result:** `No such file or directory`.

---

## 3. Pre-Boot Encryption Considerations (FileVault & BitLocker)

- **BitLocker (Windows):** When TPM+PIN or TPM-only is used, unlocking occurs at boot. Once the Windows lock screen is reached, the volume is decrypted; VanishKey temporary accounts function seamlessly.
- **FileVault (macOS):** With FileVault enabled, macOS relies on an EFI/login pre-boot environment. Only users with a secure token generated during initial setup can unlock a cold-booted disk. Because ephemeral accounts are created on an already-unlocked OS, **the Mac must be awake or at the system lock screen** (not cold-booted) for temporary users to log in.
