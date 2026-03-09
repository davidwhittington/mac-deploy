#!/usr/bin/env bash
# security-audit.sh — macOS workstation security posture audit
# Usage: bash security-audit.sh [--brief] [--save]
#   --brief  Skip package lists
#   --save   Write report to private/workstations/<hostname>-<date>.md
# Output: Markdown-formatted report (stdout by default)

set -euo pipefail

BRIEF=""
SAVE=false
for arg in "$@"; do
  [[ "$arg" == "--brief" ]] && BRIEF="--brief"
  [[ "$arg" == "--save" ]]  && SAVE=true
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "security-audit.sh — full macOS security posture audit. Outputs structured Markdown."
    echo
    echo "Usage:"
    echo "  bash scripts/audit/security-audit.sh [--brief] [--save]"
    echo
    echo "Flags:"
    echo "  --brief   Skip package lists"
    echo "  --save    Write report to private/workstations/<hostname>-<date>.md"
    echo "  --help    Show this help and exit"
    exit 0
  fi
done

HOSTNAME=$(hostname -s)
DATE=$(date +%Y-%m-%d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PRIVATE_DIR="$REPO_ROOT/private/workstations"

if $SAVE; then
  mkdir -p "$PRIVATE_DIR"
  OUTFILE="$PRIVATE_DIR/${HOSTNAME}-${DATE}.md"
  exec > >(tee "$OUTFILE")
  echo "==> Saving report to: $OUTFILE" >&2
fi

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
  BOOT=$(bputil -d 2>/dev/null | grep -i "security" | head -5 || true)
  if [[ -z "$BOOT" ]]; then
    echo "- **Status:** Unable to read without sudo — run \`sudo bputil -d\` to inspect"
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

# Bluetooth
echo "### Bluetooth"
echo
BT_STATE=$(system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/State:/ {print $2; exit}' || echo "unknown")
if echo "$BT_STATE" | grep -qi "^on$"; then
  BT_POWER="on"
  echo "- **Status:** ⚠️  ON — disable if not needed on this machine"
else
  BT_POWER="off"
  echo "- **Status:** ✅ ${BT_STATE:-Off}"
fi
echo

# Developer Mode
echo "### Developer Mode (DevToolsSecurity)"
echo
DEV_MODE=$(DevToolsSecurity -status 2>/dev/null || echo "unavailable")
echo "- **Status:** $DEV_MODE"
if echo "$DEV_MODE" | grep -qi "enabled"; then
  echo "- **Result:** ⚠️  Developer mode is enabled — expected on dev machines, flag on others"
else
  echo "- **Result:** ✅ Developer mode is disabled"
fi
echo

hr

# ── sharing services ─────────────────────────────────────────────────────────

echo "## Sharing Services"
echo

# Remote Login (SSH) — check port 22 directly; launchctl misses socket-activated sshd
if lsof -iTCP:22 -sTCP:LISTEN -P -n 2>/dev/null | grep -q sshd; then
  SSH_STATE="⚠️  ENABLED"
else
  SSH_STATE="✅ Disabled"
fi
echo "| Service | Status |"
echo "|---------|--------|"
printf "| Remote Login (SSH) | %s |\n" "$SSH_STATE"

# ARD — check listening ports (5900 VNC, 3283 ARD); launchd entry always exists
# due to SIP but OnDemand=true means it only runs when connections are accepted
if lsof -iTCP:5900 -sTCP:LISTEN -P -n 2>/dev/null | grep -q . || \
   lsof -iTCP:3283 -sTCP:LISTEN -P -n 2>/dev/null | grep -q .; then
  printf "| Remote Management (ARD) | ⚠️  ENABLED |\n"
else
  printf "| Remote Management (ARD) | ✅ Disabled |\n"
fi

# Other sharing services via launchctl
for service in \
  "com.apple.screensharing:Screen Sharing" \
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
    local val=""
    # Check drop-in files first (sorted; first value wins in sshd)
    for dropin in $(ls /etc/ssh/sshd_config.d/*.conf 2>/dev/null | sort); do
      val=$(grep -i "^${key}" "$dropin" 2>/dev/null | awk '{print $2}' | head -1 || true)
      [[ -n "$val" ]] && break
    done
    # Fall back to main sshd_config if not found in drop-ins
    if [[ -z "$val" ]]; then
      val=$(grep -i "^${key}" "$SSHD_CONF" 2>/dev/null | awk '{print $2}' | head -1 || true)
    fi
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
  check_sshd "MaxAuthTries" "3"
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
  lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==1 || !seen[$1,$9]++' || true
else
  netstat -an 2>/dev/null | grep LISTEN || true
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

# ── sensitive file permissions ────────────────────────────────────────────────

echo "## Sensitive File Permissions"
echo
echo "Checks ~/.ssh, ~/.aws, ~/.gnupg, and ~/.config/op for world-readable files."
echo "World-readable credential files are a direct path to privilege escalation."
echo

SENSITIVE_DIRS=("$HOME/.ssh" "$HOME/.aws" "$HOME/.gnupg" "$HOME/.config/op")
WORLD_READABLE_FILES=()

for dir in "${SENSITIVE_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r file; do
    WORLD_READABLE_FILES+=("$file")
  done < <(find "$dir" -maxdepth 3 \( -perm -o+r -o -perm -o+w \) -type f 2>/dev/null || true)
done

if [[ ${#WORLD_READABLE_FILES[@]} -eq 0 ]]; then
  echo "✅ No world-readable files found in sensitive directories."
else
  echo "⚠️  World-readable files found:"
  echo
  echo "\`\`\`"
  printf '%s\n' "${WORLD_READABLE_FILES[@]}"
  echo "\`\`\`"
fi
echo

hr

# ── sudoers ───────────────────────────────────────────────────────────────────

echo "## Sudoers Configuration"
echo
SUDOERS_NOPASSWD=$(grep -rh "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^[[:space:]]*#' || true)

if [[ -z "$SUDOERS_NOPASSWD" ]]; then
  echo "✅ No NOPASSWD entries found in sudoers."
else
  echo "⚠️  NOPASSWD entries detected — these users or commands can run sudo without a password:"
  echo
  echo "\`\`\`"
  echo "$SUDOERS_NOPASSWD"
  echo "\`\`\`"
fi
echo
echo "> Note: reading /etc/sudoers requires sudo. Run \`sudo visudo -c\` to inspect the full config."
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

if [[ "$AUTO_CHECK" == "1" ]]; then AUTO_CHECK_S="✅ Enabled"; else AUTO_CHECK_S="❌ Disabled ($AUTO_CHECK)"; fi
if [[ "$AUTO_DL" == "1" ]]; then AUTO_DL_S="✅ Enabled"; else AUTO_DL_S="⚠️  Disabled ($AUTO_DL)"; fi
if [[ "$AUTO_INSTALL" == "1" ]]; then AUTO_INSTALL_S="✅ Enabled"; else AUTO_INSTALL_S="⚠️  $AUTO_INSTALL"; fi
if [[ "$SEC_INSTALL" == "1" ]]; then SEC_S="✅ Enabled"; else SEC_S="⚠️  $SEC_INSTALL"; fi

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

# ARD — port-based check (launchd entry is SIP-protected and always present)
if lsof -iTCP:5900 -sTCP:LISTEN -P -n 2>/dev/null | grep -q . || \
   lsof -iTCP:3283 -sTCP:LISTEN -P -n 2>/dev/null | grep -q .; then
  finding "Remote Management (ARD) is accepting connections" "🟠 High" "Disable in System Settings → General → Sharing → Remote Management"
fi

# Other sharing services
for svc in "com.apple.screensharing" "com.apple.InternetSharing" "com.apple.remoteevents"; do
  if launchctl list "$svc" &>/dev/null; then
    case "$svc" in
      com.apple.screensharing) finding "Screen Sharing is enabled" "🟡 Medium" "Disable in System Settings → General → Sharing" ;;
      com.apple.InternetSharing) finding "Internet Sharing is enabled" "🟠 High" "Disable in System Settings → General → Sharing" ;;
      com.apple.remoteevents) finding "Remote Apple Events enabled" "🟡 Medium" "Disable in System Settings → General → Sharing" ;;
    esac
  fi
done

# SSH password auth — check drop-ins first, then main config
get_sshd_val() {
  local key="$1" val=""
  for dropin in $(ls /etc/ssh/sshd_config.d/*.conf 2>/dev/null | sort); do
    val=$(grep -i "^${key}" "$dropin" 2>/dev/null | awk '{print $2}' | head -1 || true)
    [[ -n "$val" ]] && break
  done
  [[ -z "$val" ]] && val=$(grep -i "^${key}" "$SSHD_CONF" 2>/dev/null | awk '{print $2}' | head -1 || true)
  echo "$val"
}

if [[ -f "$SSHD_CONF" ]]; then
  PASS_AUTH=$(get_sshd_val "PasswordAuthentication")
  if [[ "$PASS_AUTH" != "no" ]]; then
    finding "SSH PasswordAuthentication not explicitly disabled" "🟠 High" "Set \`PasswordAuthentication no\` in /etc/ssh/sshd_config.d/099-hardening.conf"
  fi
  ROOT_LOGIN=$(get_sshd_val "PermitRootLogin")
  if [[ "$ROOT_LOGIN" != "no" ]]; then
    finding "SSH PermitRootLogin not explicitly disabled" "🟡 Medium" "Set \`PermitRootLogin no\` in /etc/ssh/sshd_config.d/099-hardening.conf"
  fi
fi

# Bluetooth
if [[ "$BT_POWER" == "on" ]]; then
  finding "Bluetooth is on" "🟡 Medium" "Disable in System Settings → Bluetooth if not in active use"
fi

# Developer mode
if echo "$DEV_MODE" | grep -qi "enabled"; then
  finding "Developer mode enabled (DevToolsSecurity)" "🟡 Medium" "Disable on non-dev machines: \`sudo DevToolsSecurity -disable\`"
fi

# World-readable sensitive files
if [[ ${#WORLD_READABLE_FILES[@]} -gt 0 ]]; then
  finding "World-readable files in sensitive directories" "🟠 High" "Run \`chmod 600 ~/.ssh/* && chmod 700 ~/.ssh\` — review ~/.aws and ~/.gnupg similarly"
fi

# Sudoers NOPASSWD
if [[ -n "$SUDOERS_NOPASSWD" ]]; then
  finding "NOPASSWD entries in sudoers" "🟠 High" "Review with \`sudo visudo\` — remove unnecessary NOPASSWD grants"
fi

if [[ "$N" -eq 0 ]]; then
  echo "| — | No critical findings | — | Machine meets baseline |"
fi

echo
echo
echo "_End of audit report for \`$HOSTNAME\` — ${DATE}_"
