# VanishKey Distribution, Signing & Platform Architecture Guide

This guide details code-signing requirements, notarization procedures, deployment strategies, and platform-specific constraints across all target operating systems.

---

## 1. Windows Distribution & Code Signing

### EV Code Signing vs Standard Certificates
- **Microsoft SmartScreen:** Executables downloaded from the internet without an established cryptographic reputation trigger a blue "Windows protected your PC" SmartScreen warning.
- **Extended Validation (EV) Hardware Token / Cloud HSM:**
  - Modern EV certificates require a FIPS 140-2 Level 2 cryptographic hardware token (e.g. YubiKey) or a Cloud HSM (Azure Key Vault, DigiCert ONE, AWS KMS).
  - An EV-signed installer gains instant reputation in Microsoft SmartScreen, eliminating user warning popups.
- **Signing Command:**
  ```powershell
  signtool.exe sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /f "C:\Certs\VanishKey.pfx" /p "<PASSWORD>" "dist\windows\VanishKey-Setup-1.0.0.exe"
  ```

### Installer vs MSIX
- **Inno Setup (.exe):** Selected default for VanishKey. Allows easy embedding of administrative background helper scripts and registering auto-start under registry keys.
- **MSIX:** Enables Windows Store distribution and clean sandboxed installation, but requires declarative capability declarations to invoke administrative PowerShell commands.

---

## 2. macOS Distribution, Signing & Notarization

### Apple Developer Program Requirement
- Apple enforces **Gatekeeper** on all modern macOS versions (macOS 12 Monterey through macOS 15 Sequoia).
- Unsigned or unnotarized binaries will be blocked with: *"VanishKey.app cannot be opened because Apple cannot check it for malicious software."*

### Step-by-Step Signing & Notarization Workflow
1. **Developer ID Application Certificate:**
   Obtain a `Developer ID Application: <TeamName> (<TeamID>)` certificate from developer.apple.com.
2. **Sign with Hardened Runtime & Entitlements:**
   ```bash
   codesign --deep --force --verify --verbose \
     --sign "Developer ID Application: VanishKey Inc. (TEAM_ID)" \
     --options runtime \
     --entitlements packaging/macos/Entitlements.plist \
     "build/macos/Build/Products/Release/VanishKey.app"
   ```
3. **Submit to Apple Notary Service:**
   ```bash
   xcrun notarytool submit "dist/macos/VanishKey-macOS.dmg" \
     --apple-id "developer@vanishkey.com" \
     --password "app-specific-password" \
     --team-id "TEAM_ID" \
     --wait
   ```
4. **Staple Notarization Ticket:**
   ```bash
   xcrun stapler staple "dist/macos/VanishKey-macOS.dmg"
   ```

---

## 3. Mobile Distribution (Android & iOS)

### Android Sideloading vs Google Play Store
- **Sideloading (`.apk`):**
  - Roommates can install the APK directly by enabling *"Install from Unknown Sources"* on their Android device.
  - Generates a Google Play Protect prompt on initial install until scanned.
- **Google Play Store (`.aab`):**
  - Distribute via Google Play Console **Internal Testing Track** (up to 100 testers without formal public app review).
  - Zero sideloading hurdles, automatic updates.

### iOS Distribution (TestFlight vs Ad-Hoc Provisioning)
- **iOS Sideloading Limits:** iOS strictly prohibits direct browser-downloaded `.ipa` execution without enterprise certificates or developer device provisioning.
- **TestFlight (Recommended):**
  - Requires an active Apple Developer Program membership ($99/year).
  - Internal testing track allows immediate deployment to up to 100 team members with zero review.
  - External public link testing allows up to 10,000 testers with a brief Apple metadata review.
- **Ad-Hoc Distribution:**
  - Hard limit of 100 registered device UDIDs per device category per membership year. Requires compiling with explicit device UDIDs embedded in the `.mobileprovision` file.

---

## 4. Platform Constraints & Hardware Edge Cases

### macOS: FileVault Pre-Boot Disk Encryption
- **Constraint:** FileVault relies on an APFS Pre-Boot volume. When a FileVault-encrypted Mac boots from a cold power-off state, only pre-authorized users with Secure Tokens (or an iCloud recovery key) can unlock the encrypted disk.
- **VanishKey Solution:** VanishKey is designed for when the laptop is already **awake or sitting at the locked login screen**. When awake, the APFS disk is already unlocked and running; creating a temporary user with `sysadminctl` allows instant login from the lock screen.
- **Advanced Pre-Boot SSH Mode:** If the Mac is cold-booted, pre-boot SSH or Wake-on-LAN is required to deliver the disk unlock payload.

### Windows: BitLocker Drive Encryption
- When BitLocker is configured with TPM (standard on all modern Windows laptops), the drive unlocks automatically during boot up to the Windows Lock Screen.
- Once the Windows Lock Screen appears, VanishKey's ephemeral local account operates with 100% functionality.

---

## 5. Desktop Agent Architecture: Flutter vs Tauri

| Metric | Flutter Desktop | Tauri (Rust + Webview2 / WebKit) |
| :--- | :--- | :--- |
| **Installed Disk Size** | ~70 MB – 110 MB | **~12 MB – 25 MB** |
| **Idle RAM Footprint** | ~65 MB – 85 MB | **~25 MB – 35 MB** |
| **Codebase Sharing** | Shares Flutter/Dart codebase with mobile app | Requires Rust backend + HTML/React/Vue frontend |
| **Native API Access** | Windows/macOS plugins (tray, process runner) | High-performance Rust native syscalls |

### Architectural Recommendation:
- If installed bundle size must be kept strictly **under 30 MB**, **Tauri** is the premier alternative to Flutter for the desktop host.
- However, using Flutter for both Mobile and Desktop enables **90% code reuse** across message schemas, crypto logic, and UI design systems, while staying comfortably near the ~80 MB installed footprint.
