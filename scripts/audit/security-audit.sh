#!/usr/bin/env bash
# security-audit.sh — macOS workstation security posture audit
# Usage: bash security-audit.sh [--brief]
# Output: Markdown-formatted report suitable for docs/workstations/<hostname>.md

set -euo pipefail

BRIEF=${1:-""}
HOSTNAME=$(hostname -s)
DATE=$(date +%Y-%m-%d)

# ── helpers ──────────────────────────────────────────────────────────────────

check() {
  # check <command> — run silently, return output or "ERROR"
  eval "$*" 2>/dev/null || echo "ERROR (requires sudo or unavailable)"
}

status_icon() {
  # status_icon <string to match> <haystack>
  echo "$2" | grep -qi "$1" && echo "✅ ENABLED" || echo "❌ DISABLED"
}

hr() { echo; echo "---"; echo; }

# ── header ───────────────────────────────────────────────────────────────────

cat <<EOF
# Workstation: \`$HOSTNAME\`

> Generated: $DATE | Script: \`scripts/audit/security-audit.sh\`

EOF

# ── hardware & software ──────────────────────────────────────────────────────

echo "## Hardware & Software"
echo
echo "| Field | Value |"
echo "|-------|-------|"
echo "| Hostname | \`$HOSTNAME\` |"
echo "| Model | $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}') |"
echo "| CPU | $(sysctl -n machdep.cpu.brand_string 2>/dev/null || system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ {print $2; exit}') |"
echo "| RAM | $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Memory/ {print $2; exit}') |"
echo "| macOS Version | $(sw_vers -productVersion) ($(sw_vers -productName)) |"
echo "| Build | $(sw_vers -buildVersion) |"
echo "| Architecture | $(uname -m) |"
echo "| Shell | $SHELL |"
echo "| Hostname (full) | $(hostname) |"

# Homebrew
if command -v brew &>/dev/null; then
  echo "| Homebrew | $(brew --version | head -1) |"
else
  echo "| Homebrew | ❌ Not installed |"
fi

# Xcode CLT
if xcode-select -p &>/dev/null; then
  echo "| Xcode CLT | $(xcodebuild -version 2>/dev/null | head -1 || echo "Installed") |"
else
  echo "| Xcode CLT | ❌ Not installed |"
fi

hr

# ── security posture ─────────────────────────────────────────────────────────

echo "## Security Posture"
echo

# FileVault
echo "### Disk Encryption (FileVault)"
echo
FV=$(check fdesetup status)
echo "- **Status:** $FV"
if echo "$FV" | grep -qi "On"; then
  echo "- **Result:** ✅ FileVault is enabled"
else
  echo "- **Result:** ❌ FileVault is DISABLED — disk is unencrypted"
fi
echo

# SIP
echo "### System Integrity Protection (SIP)"
echo
SIP=$(check csrutil status)
echo "- **Status:** $SIP"
if echo "$SIP" | grep -qi "enabled"; then
  echo "- **Result:** ✅ SIP is enabled"
else
  echo "- **Result:** ❌ SIP is DISABLED — system protections are off"
fi
echo

# Gatekeeper
echo "### Gatekeeper"
echo
GK=$(check spctl --status)
echo "- **Status:** $GK"
if echo "$GK" | grep -qi "enabled\|assessments enabled"; then
  echo "- **Result:** ✅ Gatekeeper is enabled"
else
  echo "- **Result:** ❌ Gatekeeper is DISABLED"
fi
echo

# Secure Boot (Apple Silicon / T2)
echo "### Secure Boot"
echo
if [[ "$(uname -m)" == "arm64" ]]; then
  BOOT=$(check bputil -d 2>/dev/null | grep -i "security" | head -5)
  if [[ -z "$BOOT" ]]; then
    echo "- **Status:** Unable to read (try with sudo)"
  else
    echo "\`\`\`"
    echo "$BOOT"
    echo "\`\`\`"
  fi
else
  echo "- **Status:** Intel Mac — check via Recovery Mode / Startup Security Utility"
fi
echo

# Application Firewall
echo "### Application Firewall"
echo
FW_STATE=$(check /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate)
FW_STEALTH=$(check /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode)
FW_BLOCK=$(check /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall)
echo "| Setting | Status |"
echo "|---------|--------|"
echo "| Global State | $FW_STATE |"
echo "| Stealth Mode | $FW_STEALTH |"
echo "| Block All Incoming | $FW_BLOCK |"
echo

hr

# ── sharing services ─────────────────────────────────────────────────────────

echo "## Sharing Services"
echo

# Remote Login (SSH)
SSH_STATE=$(check systemsetup -getremotelogin 2>/dev/null || launchctl list com.openssh.sshd 2>/dev/null | grep -q "PID" && echo "On" || echo "Off")
echo "| Service | Status |"
echo "|---------|--------|"
printf "| Remote Login (SSH) | %s |\n" "$SSH_STATE"

# Check other sharing services via launchctl / system_profiler
for service in \
  "com.apple.screensharing:Screen Sharing" \
  "com.apple.RemoteDesktop.agent:Remote Management (ARD)" \
  "com.apple.smbd:File Sharing (SMB)" \
  "com.apple.AppleFileServer:File Sharing (AFP)" \
  "com.apple.remoteevents:Remote Apple Events" \
  "com.apple.InternetSharing:Internet Sharing"
do
  svc_id="${service%%:*}"
  svc_name="${service##*:}"
  if launchctl list "$svc_id" &>/dev/null; then
    printf "| %s | ⚠️  ENABLED |\n" "$svc_name"
  else
    printf "| %s | ✅ Disabled |\n" "$svc_name"
  fi
done

echo

hr

# ── SSH configuration ─────────────────────────────────────────────────────────

echo "## SSH Server Configuration"
echo
SSHD_CONF="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CONF" ]]; then
  echo "| Setting | Value | Assessment |"
  echo "|---------|-------|------------|"

  check_sshd() {
    local key="$1"
    local good_val="$2"
    local val
    val=$(grep -i "^${key}" "$SSHD_CONF" 2>/dev/null | awk '{print $2}' | head -1)
    val="${val:-<default>}"
    if [[ "$val" == "$good_val" ]] || [[ "$val" == "<default>" && "$good_val" == "<default>" ]]; then
      icon="✅"
    else
      icon="⚠️ "
    fi
    printf "| %s | \`%s\` | %s |\n" "$key" "$val" "$icon"
  }

  check_sshd "PasswordAuthentication" "no"
  check_sshd "PermitRootLogin" "no"
  check_sshd "PubkeyAuthentication" "yes"
  check_sshd "ChallengeResponseAuthentication" "no"
  check_sshd "UsePAM" "<default>"
  check_sshd "Port" "22"
  check_sshd "AllowUsers" "<default>"
  check_sshd "MaxAuthTries" "<default>"
else
  echo "- \`/etc/ssh/sshd_config\` not found (SSH may not be installed/enabled)"
fi
echo

hr

# ── listening ports ───────────────────────────────────────────────────────────

echo "## Listening Services & Open Ports"
echo
echo "\`\`\`"
if command -v lsof &>/dev/null; then
  sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==1 || !seen[$1,$9]++' || \
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==1 || !seen[$1,$9]++'
else
  netstat -an | grep LISTEN
fi
echo "\`\`\`"
echo

hr

# ── installed packages ────────────────────────────────────────────────────────

if [[ "$BRIEF" != "--brief" ]]; then

echo "## Homebrew Packages"
echo
if command -v brew &>/dev/null; then
  echo "### Formulae"
  echo "\`\`\`"
  brew list --formula 2>/dev/null
  echo "\`\`\`"
  echo
  echo "### Casks"
  echo "\`\`\`"
  brew list --cask 2>/dev/null
  echo "\`\`\`"
else
  echo "- Homebrew not installed"
fi

hr

fi  # end --brief skip

# ── user accounts ─────────────────────────────────────────────────────────────

echo "## User Accounts"
echo
echo "\`\`\`"
dscl . list /Users | grep -v '^_' | grep -v 'daemon\|nobody\|root'
echo "\`\`\`"
echo

# Admin users
echo "**Admin users:**"
echo "\`\`\`"
dscl . read /Groups/admin GroupMembership 2>/dev/null
echo "\`\`\`"
echo

hr

# ── macos updates ─────────────────────────────────────────────────────────────

echo "## macOS Updates"
echo
echo "| Setting | Value |"
echo "|---------|-------|"

AUTO_CHECK=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null || echo "unknown")
AUTO_DL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo "unknown")
AUTO_INSTALL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null || echo "unknown")
SEC_INSTALL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall 2>/dev/null || echo "unknown")

[[ "$AUTO_CHECK" == "1" ]] && AUTO_CHECK_S="✅ Enabled" || AUTO_CHECK_S="❌ Disabled ($AUTO_CHECK)"
[[ "$AUTO_DL" == "1" ]] && AUTO_DL_S="✅ Enabled" || AUTO_DL_S="⚠️  Disabled ($AUTO_DL)"
[[ "$AUTO_INSTALL" == "1" ]] && AUTO_INSTALL_S="✅ Enabled" || AUTO_INSTALL_S="⚠️  $AUTO_INSTALL"
[[ "$SEC_INSTALL" == "1" ]] && SEC_S="✅ Enabled" || SEC_S="⚠️  $SEC_INSTALL"

echo "| Automatic Check | $AUTO_CHECK_S |"
echo "| Automatic Download | $AUTO_DL_S |"
echo "| Automatic macOS Updates | $AUTO_INSTALL_S |"
echo "| Security Data Install | $SEC_S |"

echo

hr

# ── findings summary ──────────────────────────────────────────────────────────

echo "## Findings Summary"
echo
echo "| # | Finding | Severity | Recommendation |"
echo "|---|---------|----------|----------------|"

N=0
finding() {
  N=$((N+1))
  printf "| %d | %s | %s | %s |\n" "$N" "$1" "$2" "$3"
}

# FileVault check
if ! echo "$FV" | grep -qi "On"; then
  finding "FileVault disabled — disk unencrypted" "🔴 Critical" "Enable FileVault in System Settings → Privacy & Security"
fi

# SIP check
if ! echo "$SIP" | grep -qi "enabled"; then
  finding "SIP disabled" "🔴 Critical" "Re-enable via Recovery Mode: \`csrutil enable\`"
fi

# Gatekeeper check
if ! echo "$GK" | grep -qi "enabled\|assessments enabled"; then
  finding "Gatekeeper disabled" "🟠 High" "Enable: \`sudo spctl --master-enable\`"
fi

# Firewall check
if ! echo "$FW_STATE" | grep -qi "enabled"; then
  finding "Application Firewall disabled" "🟠 High" "Enable in System Settings → Network → Firewall"
fi

# Sharing services
for svc in "com.apple.screensharing" "com.apple.RemoteDesktop.agent" "com.apple.InternetSharing" "com.apple.remoteevents"; do
  if launchctl list "$svc" &>/dev/null; then
    case "$svc" in
      com.apple.screensharing) finding "Screen Sharing is enabled" "🟡 Medium" "Disable unless required: System Settings → Sharing" ;;
      com.apple.RemoteDesktop.agent) finding "Remote Management (ARD) is enabled" "🟠 High" "Disable if not needed: \`sudo kickstart -deactivate\`" ;;
      com.apple.InternetSharing) finding "Internet Sharing is enabled" "🟠 High" "Disable in System Settings → Sharing" ;;
      com.apple.remoteevents) finding "Remote Apple Events enabled" "🟡 Medium" "Disable in System Settings → Sharing" ;;
    esac
  fi
done

# SSH password auth
if [[ -f "$SSHD_CONF" ]]; then
  PASS_AUTH=$(grep -i "^PasswordAuthentication" "$SSHD_CONF" 2>/dev/null | awk '{print $2}' | head -1)
  if [[ "$PASS_AUTH" != "no" ]]; then
    finding "SSH PasswordAuthentication not explicitly disabled" "🟠 High" "Set \`PasswordAuthentication no\` in /etc/ssh/sshd_config"
  fi
  ROOT_LOGIN=$(grep -i "^PermitRootLogin" "$SSHD_CONF" 2>/dev/null | awk '{print $2}' | head -1)
  if [[ "$ROOT_LOGIN" != "no" ]]; then
    finding "SSH PermitRootLogin not explicitly disabled" "🟡 Medium" "Set \`PermitRootLogin no\` in /etc/ssh/sshd_config"
  fi
fi

if [[ "$N" -eq 0 ]]; then
  echo "| — | No critical findings | — | Machine meets baseline |"
fi

echo
echo
echo "_End of audit report for \`$HOSTNAME\` — $DATE_"
