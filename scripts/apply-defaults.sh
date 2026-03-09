#!/usr/bin/env bash
# apply-defaults.sh — apply hardened macOS system defaults
#
# What this script does:
#   Writes macOS system preferences via `defaults write` to enforce a secure,
#   consistent baseline across lab workstations. Changes take effect after
#   logging out/in, or immediately for most settings.
#
#   Categories covered:
#     - Screen lock and password policy
#     - Screenshot location (moved out of ~/Desktop)
#     - Finder security settings
#     - Safari security (if installed)
#     - Firewall logging
#     - Remote content blocking in Mail
#     - AirDrop restrictions
#     - Software update policy
#     - Crash reporter behavior
#
# Usage:
#   bash scripts/apply-defaults.sh [--dry-run]
#   --dry-run   Print each default that would be written without applying it
#
# Requirements: some settings require sudo (SoftwareUpdate, screensaver policy).
# Run with sudo for the full set, or without for user-level settings only.
#
# To undo: most settings can be reset via System Settings, or use:
#   defaults delete <domain> <key>

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ── helpers ───────────────────────────────────────────────────────────────────

APPLIED=0
SKIPPED=0

pref() {
  # pref <description> <domain> <key> <type> <value>
  local desc="$1" domain="$2" key="$3" type="$4" value="$5"
  if $DRY_RUN; then
    printf "  [dry-run] %-55s defaults write %s %s -%s %s\n" "$desc" "$domain" "$key" "$type" "$value"
    SKIPPED=$((SKIPPED+1))
  else
    defaults write "$domain" "$key" "-${type}" "$value" 2>/dev/null && \
      printf "  ✓ %s\n" "$desc" && APPLIED=$((APPLIED+1)) || \
      printf "  ✗ %s (failed — may need sudo or unavailable on this macOS version)\n" "$desc"
  fi
}

sudo_pref() {
  # sudo_pref <description> <domain> <key> <type> <value>
  local desc="$1" domain="$2" key="$3" type="$4" value="$5"
  if [[ "$EUID" -ne 0 ]]; then
    printf "  — %s (skipped — requires sudo)\n" "$desc"
    return
  fi
  pref "$desc" "$domain" "$key" "$type" "$value"
}

# ── header ────────────────────────────────────────────────────────────────────

echo
echo "=== macOS System Defaults ==="
echo
echo "Machine: $(hostname -s)"
$DRY_RUN && echo "Mode:    DRY RUN — no changes will be written"
[[ "$EUID" -ne 0 ]] && echo "Note:    Running without sudo — system-level settings will be skipped."
echo

# ── screen lock & password ────────────────────────────────────────────────────

echo "--- Screen Lock & Password ---"
echo

# Require password immediately after sleep or screensaver
pref \
  "Require password immediately after sleep/screensaver" \
  "com.apple.screensaver" askForPassword int 1

pref \
  "Password delay: 0 seconds (immediate)" \
  "com.apple.screensaver" askForPasswordDelay int 0

# Set screensaver to activate after 5 minutes of inactivity
pref \
  "Screensaver idle time: 5 minutes" \
  "com.apple.screensaver" idleTime int 300

echo

# ── screenshots ───────────────────────────────────────────────────────────────

echo "--- Screenshots ---"
echo

# Move screenshots out of ~/Desktop into ~/Documents/Screenshots
SCREENSHOTS_DIR="$HOME/Documents/Screenshots"
mkdir -p "$SCREENSHOTS_DIR"
pref \
  "Screenshot save location: ~/Documents/Screenshots" \
  "com.apple.screencapture" location string "$SCREENSHOTS_DIR"

# Disable screenshot shadow (minor, but keeps filenames cleaner)
pref \
  "Disable screenshot drop shadows" \
  "com.apple.screencapture" disable-shadow bool true

echo

# ── finder ────────────────────────────────────────────────────────────────────

echo "--- Finder ---"
echo

# Show all filename extensions
pref \
  "Show all file extensions" \
  "NSGlobalDomain" AppleShowAllExtensions bool true

# Warn before changing a file extension
pref \
  "Warn before changing file extension" \
  "com.apple.finder" FXEnableExtensionChangeWarning bool true

# Show hidden files (useful for auditing)
pref \
  "Show hidden files" \
  "com.apple.finder" AppleShowAllFiles bool true

# Disable the warning before emptying Trash
pref \
  "Warn before emptying Trash" \
  "com.apple.finder" WarnOnEmptyTrash bool true

# Show full path in Finder window title
pref \
  "Show full POSIX path in Finder title bar" \
  "com.apple.finder" _FXShowPosixPathInTitle bool true

echo

# ── airdrop ───────────────────────────────────────────────────────────────────

echo "--- AirDrop ---"
echo

# Restrict AirDrop to contacts only (not Everyone)
pref \
  "AirDrop discoverability: contacts only" \
  "com.apple.sharingd" DiscoverableMode string "Contacts Only"

echo

# ── mail ──────────────────────────────────────────────────────────────────────

echo "--- Mail ---"
echo

# Disable loading remote content in emails (prevents tracking pixels)
pref \
  "Disable remote image loading in Mail" \
  "com.apple.mail" DisableURLLoading bool true

echo

# ── safari ────────────────────────────────────────────────────────────────────

echo "--- Safari ---"
echo

# Do not open files automatically after downloading
pref \
  "Safari: do not auto-open safe files after download" \
  "com.apple.Safari" AutoOpenSafeDownloads bool false

# Enable Safari fraudulent site warnings
pref \
  "Safari: enable fraudulent website warnings" \
  "com.apple.Safari" WarnAboutFraudulentWebsites bool true

# Disable sending search queries to Apple
pref \
  "Safari: disable sending search queries to Apple" \
  "com.apple.Safari" UniversalSearchEnabled bool false

# Show full URL in Safari address bar
pref \
  "Safari: show full URL in address bar" \
  "com.apple.Safari" ShowFullURLInSmartSearchField bool true

echo

# ── crash reporter ────────────────────────────────────────────────────────────

echo "--- Crash Reporter ---"
echo

# Send crash reports to Apple (set to none to disable)
pref \
  "Crash Reporter: move to notification center only" \
  "com.apple.CrashReporter" UseUNC int 1

echo

# ── software update (requires sudo) ───────────────────────────────────────────

echo "--- Software Update (requires sudo) ---"
echo

sudo_pref \
  "Auto-check for updates: enabled" \
  "/Library/Preferences/com.apple.SoftwareUpdate" AutomaticCheckEnabled int 1

sudo_pref \
  "Auto-download updates: enabled" \
  "/Library/Preferences/com.apple.SoftwareUpdate" AutomaticDownload int 1

sudo_pref \
  "Install security data updates automatically" \
  "/Library/Preferences/com.apple.SoftwareUpdate" ConfigDataInstall int 1

sudo_pref \
  "Install critical system updates automatically" \
  "/Library/Preferences/com.apple.SoftwareUpdate" CriticalUpdateInstall int 1

echo

# ── apply ─────────────────────────────────────────────────────────────────────

if ! $DRY_RUN; then
  # Restart affected services to pick up changes
  killall Finder 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo
if $DRY_RUN; then
  echo "Dry run complete. Remove --dry-run to apply."
else
  echo "Done. $APPLIED setting(s) applied."
  echo
  echo "Some changes (screensaver, Finder) take effect immediately."
  echo "Log out and back in to ensure all settings are active."
  echo
  echo "Verify with the security audit:"
  echo "  bash scripts/audit/security-audit.sh --brief"
fi
echo
