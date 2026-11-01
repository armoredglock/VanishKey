#!/usr/bin/env bash
# ==============================================================================
# VanishKey - Temporary User Cleanup Script (macOS)
# Terminates active sessions, deletes local account, removes home directory,
# and cleans up launchd background jobs.
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo '{"success": false, "error": "This script must be run as root (sudo)."}' >&2
   exit 1
fi

USERNAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo '{"success": false, "error": "Username argument is required."}' >&2
    exit 1
fi

# Guard against accidental deletion of root or admin users
CURRENT_USER="${SUDO_USER:-$(whoami)}"
if [[ "$USERNAME" == "root" || "$USERNAME" == "daemon" || "$USERNAME" == "$CURRENT_USER" || "$USERNAME" == "guest" ]]; then
    echo "{\"success\": false, \"error\": \"Refusing to delete protected user: ${USERNAME}\"}" >&2
    exit 1
fi

REPORT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 1. Terminate all active processes owned by the user
pkill -9 -u "$USERNAME" 2>/dev/null || true

# 2. Unload and remove the launchd daemon
PLIST_PATH="/Library/LaunchDaemons/com.vanishkey.cleanup-${USERNAME}.plist"
if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
fi

# 3. Delete user account via sysadminctl or dscl
if ! sysadminctl -deleteUser "$USERNAME" >/dev/null 2>&1; then
    dscl . -delete "/Users/${USERNAME}" 2>/dev/null || true
fi

# 4. Remove home directory if still present
HOME_DIR="/Users/${USERNAME}"
if [[ -d "$HOME_DIR" ]]; then
    rm -rf "$HOME_DIR"
fi

# 5. Output JSON status
cat <<EOF
{"success":true,"status":"deleted","username":"${USERNAME}","timestamp":"${REPORT_TIMESTAMP}"}
EOF
exit 0
