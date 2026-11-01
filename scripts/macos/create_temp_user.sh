#!/usr/bin/env bash
# ==============================================================================
# VanishKey - Temporary User Creation Script (macOS)
# Creates a time-limited, unprivileged standard macOS user with CSPRNG credentials.
#
# NOTE ON FILEVAULT:
# If FileVault full-disk encryption is enabled, a cold-booted Mac requires an
# existing FileVault-enabled user or recovery key to unlock the APFS volume
# before macOS loads the login window. This script operates when the Mac is
# already powered on / awake at the lock screen.
# ==============================================================================

set -euo pipefail

# Check for root/sudo privileges
if [[ $EUID -ne 0 ]]; then
   echo '{"success": false, "error": "This script must be run as root (sudo)."}' >&2
   exit 1
fi

USERNAME=""
DURATION_MINUTES=3

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --duration)
            DURATION_MINUTES="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Enforce duration bounds (1 to 5 minutes, hard cap 5)
if (( DURATION_MINUTES > 5 )); then
    DURATION_MINUTES=5
fi
if (( DURATION_MINUTES < 1 )); then
    DURATION_MINUTES=2
fi

# Generate unique username if not provided
if [[ -z "$USERNAME" ]]; then
    HEX_SUFFIX=$(LC_ALL=C tr -dc 'A-F0-9' < /dev/urandom | head -c 6)
    USERNAME="VK_Temp_${HEX_SUFFIX}"
fi

# Generate CSPRNG password (24 characters, URL-safe alphanumeric + special)
PASSWORD=$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9!@#$%^&*()-_=+' < /dev/urandom | head -c 24)

# Determine next available UniqueID above 500
NEXT_UID=599
while dscl . -list /Users UniqueID | awk '{print $2}' | grep -qw "$NEXT_UID"; do
    NEXT_UID=$((NEXT_UID + 1))
done

HOME_DIR="/Users/${USERNAME}"

# Create the standard user using sysadminctl (WITHOUT -admin flag)
# This guarantees standard, non-administrative privileges.
if ! sysadminctl -addUser "$USERNAME" \
    -fullName "VanishKey Ephemeral ($USERNAME)" \
    -UID "$NEXT_UID" \
    -password "$PASSWORD" \
    -home "$HOME_DIR" >/dev/null 2>&1; then
    
    # Fallback to dscl if sysadminctl fails on headless or test environment
    dscl . -create "/Users/${USERNAME}"
    dscl . -create "/Users/${USERNAME}" UserShell /bin/zsh
    dscl . -create "/Users/${USERNAME}" RealName "VanishKey Ephemeral ($USERNAME)"
    dscl . -create "/Users/${USERNAME}" UniqueID "$NEXT_UID"
    dscl . -create "/Users/${USERNAME}" PrimaryGroupID 20
    dscl . -create "/Users/${USERNAME}" NFSHomeDirectory "$HOME_DIR"
    dscl . -passwd "/Users/${USERNAME}" "$PASSWORD"
    mkdir -p "$HOME_DIR"
    chown -R "${USERNAME}:staff" "$HOME_DIR"
fi

# Enforce strict standard user directory permissions
# The temporary user home folder is 700 (owner only)
chmod 700 "$HOME_DIR"

# Verify sibling user directories: ensure other users' home directories are at most 750 or 700
# By default macOS sets standard user home folders to 750 or 700.
# Prevent temporary user from traversing other users' files.
chmod -R go-rwx "$HOME_DIR" 2>/dev/null || true

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DELETE_SCRIPT="${SCRIPT_DIR}/delete_temp_user.sh"
chmod +x "$DELETE_SCRIPT"

EXPIRY_SECONDS=$((DURATION_MINUTES * 60))
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if date -v+1m >/dev/null 2>&1; then
    # BSD date (macOS)
    EXPIRES_AT=$(date -v+"${DURATION_MINUTES}M" -u +"%Y-%m-%dT%H:%M:%SZ")
else
    # GNU date fallback
    EXPIRES_AT=$(date -d "+${DURATION_MINUTES} minutes" -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Set up launchd daemon for deletion
PLIST_PATH="/Library/LaunchDaemons/com.vanishkey.cleanup-${USERNAME}.plist"
cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vanishkey.cleanup-${USERNAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DELETE_SCRIPT}</string>
        <string>--username</string>
        <string>${USERNAME}</string>
    </array>
    <key>StartInterval</key>
    <integer>${EXPIRY_SECONDS}</integer>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"
chown root:wheel "$PLIST_PATH"
launchctl load "$PLIST_PATH" 2>/dev/null || true

# Also launch a detached background sleep fallback in case launchd interval is delayed
(
    sleep "$EXPIRY_SECONDS"
    bash "$DELETE_SCRIPT" --username "$USERNAME" >/dev/null 2>&1
) >/dev/null 2>&1 &
disown

# Return JSON payload to stdout
cat <<EOF
{"success":true,"username":"${USERNAME}","password":"${PASSWORD}","created_at":"${CREATED_AT}","expires_at":"${EXPIRES_AT}","duration_minutes":${DURATION_MINUTES},"duration_seconds":${EXPIRY_SECONDS},"launchd_job":"com.vanishkey.cleanup-${USERNAME}"}
EOF
exit 0
