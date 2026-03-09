#!/usr/bin/env bash
# first-run.sh — bootstrap a new or freshly wiped Mac to the mac-security security baseline
#
# What this script does, in order:
#   1. Checks macOS version and architecture
#   2. Installs Homebrew if not present
#   3. Taps davidwhittington/mac-security and installs the tools
#   4. Runs a security audit and shows the Findings Summary
#   5. Offers to apply SSH hardening (harden-sshd.sh)
#   6. Offers to enable the Application Firewall with stealth mode
#   7. Re-runs the audit to confirm the baseline is met
#
# Usage:
#   bash scripts/first-run.sh            # interactive (prompts before each step)
#   bash scripts/first-run.sh --auto     # apply all hardening without prompting
#   bash scripts/first-run.sh --audit-only  # audit only, no hardening
#
# Notes:
#   - SSH hardening requires sudo
#   - Firewall hardening requires sudo
#   - Run from the repo root if you've cloned mac-security; or download and run standalone

set -uo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

AUTO=false
AUDIT_ONLY=false
CONFIRM=false
for arg in "${@:-}"; do
  [[ "$arg" == "--auto" ]]       && AUTO=true
  [[ "$arg" == "--audit-only" ]] && AUDIT_ONLY=true
  [[ "$arg" == "--confirm" ]]    && CONFIRM=true
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    cat <<'HELPBANNER'

  ╔══════════════════════════════════════════════════════╗
  ║           mac-security — first-run bootstrap          ║
  ║    macOS workstation security hardening toolkit      ║
  ╚══════════════════════════════════════════════════════╝

HELPBANNER
    echo "Bootstrap a new or freshly wiped Mac to the mac-security security baseline."
    echo
    echo "Usage:"
    echo "  bash scripts/first-run.sh [--auto] [--audit-only] [--confirm]"
    echo
    echo "Flags:"
    echo "  --auto         Apply all hardening steps without prompting"
    echo "  --audit-only   Run the security audit only, skip all hardening"
    echo "  --confirm      Pass --confirm to sub-scripts (skips their confirmation prompts)"
    echo "  --help         Show this help and exit"
    exit 0
  fi
done

# When --auto is set, sub-scripts should also skip their confirmation prompts
$AUTO && CONFIRM=true

# ── helpers ───────────────────────────────────────────────────────────────────

hr()     { echo; echo "────────────────────────────────────────────────────"; echo; }
header() { hr; echo "  $1"; hr; }

confirm() {
  # confirm <prompt> — returns 0 (yes) or 1 (no)
  # In --auto mode, always returns 0
  if $AUTO; then
    echo "$1 [auto: yes]"
    return 0
  fi
  printf "%s [y/N] " "$1"
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

# ── header ────────────────────────────────────────────────────────────────────

clear
cat <<'BANNER'

  ╔══════════════════════════════════════════════════════╗
  ║           mac-security — first-run bootstrap          ║
  ║    macOS workstation security hardening toolkit      ║
  ╚══════════════════════════════════════════════════════╝

  This script will:
    1. Verify your macOS environment
    2. Install Homebrew (if needed)
    3. Install mac-security tools via Homebrew tap
    4. Run a security audit on this machine
    5. Offer to harden SSH configuration
    6. Offer to enable the Application Firewall
    7. Re-audit to confirm the baseline is met

  Nothing destructive happens without your confirmation.
  Run with --auto to apply all steps without prompting.
  Run with --audit-only to skip all hardening.

BANNER

if ! confirm "Ready to begin?"; then
  echo "Aborted."
  exit 0
fi

# ── step 1: environment ───────────────────────────────────────────────────────

header "Step 1 — Environment Check"

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_NAME=$(sw_vers -productName)
ARCH=$(uname -m)

echo "  macOS:        $MACOS_NAME $MACOS_VERSION"
echo "  Architecture: $ARCH"
echo "  Hostname:     $(hostname -s)"
echo "  Shell:        $SHELL"
echo

# Require macOS 12 or later
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 12 ]]; then
  echo "ERROR: macOS 12 (Ventura) or later required. Found: $MACOS_VERSION" >&2
  exit 1
fi

echo "  System OK."

# ── step 2: homebrew ─────────────────────────────────────────────────────────

header "Step 2 — Homebrew"

if command -v brew &>/dev/null; then
  echo "  Homebrew is already installed: $(brew --version | head -1)"
  echo "  Updating..."
  brew update --quiet 2>/dev/null | tail -3 || true
else
  echo "  Homebrew not found."
  echo
  echo "  Homebrew is a package manager for macOS. It's required to install"
  echo "  mac-security and keep it updated. The installer script is fetched from"
  echo "  https://brew.sh — review it at https://github.com/Homebrew/install"
  echo
  if confirm "  Install Homebrew now?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    if [[ "$ARCH" == "arm64" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    echo "  Homebrew installed."
  else
    echo "  Skipping Homebrew. Audit and hardening scripts will run from the repo."
  fi
fi

# ── step 3: mac-security tools ────────────────────────────────────────────────

header "Step 3 — mac-security Tools"

if command -v brew &>/dev/null; then
  echo "  Tapping davidwhittington/mac-security..."
  brew tap davidwhittington/mac-security --quiet 2>/dev/null || true

  if brew list mac-security &>/dev/null; then
    echo "  mac-security is already installed."
    echo "  Checking for updates..."
    brew upgrade mac-security 2>/dev/null | tail -3 || echo "  Already at latest version."
  else
    echo "  Installing mac-security..."
    brew install mac-security --quiet
    echo "  Installed: mac-security-audit, mac-security-capture, mac-security-deploy"
  fi
else
  echo "  Homebrew not available — tools will run from repo scripts."
fi

# ── step 4: security audit ────────────────────────────────────────────────────

header "Step 4 — Security Audit"

echo "  Running a full security audit on this machine..."
echo "  This checks: FileVault, SIP, Gatekeeper, Firewall, SSH, sharing services,"
echo "  open ports, user accounts, and macOS update policy."
echo

# Find the audit script — prefer installed version, fall back to repo
AUDIT_CMD=""
if command -v mac-security-audit &>/dev/null; then
  AUDIT_CMD="mac-security-audit"
elif [[ -f "$(dirname "$0")/../scripts/audit/security-audit.sh" ]]; then
  AUDIT_CMD="bash $(dirname "$0")/audit/security-audit.sh"
elif [[ -f "scripts/audit/security-audit.sh" ]]; then
  AUDIT_CMD="bash scripts/audit/security-audit.sh"
fi

if [[ -z "$AUDIT_CMD" ]]; then
  echo "  WARNING: audit script not found — skipping audit step."
  AUDIT_FINDINGS="(audit not run)"
else
  AUDIT_OUTPUT=$(eval "$AUDIT_CMD --brief" 2>/dev/null)
  FINDINGS=$(echo "$AUDIT_OUTPUT" | awk '/## Findings Summary/,0')
  echo "$FINDINGS"
fi

if $AUDIT_ONLY; then
  echo
  echo "  --audit-only specified. Hardening steps skipped."
  echo "  Run without --audit-only to apply hardening."
  echo
  exit 0
fi

# ── step 5: ssh hardening ─────────────────────────────────────────────────────

header "Step 5 — SSH Hardening"

cat <<'INFO'
  What SSH hardening does:
    - Disables password authentication (keys only)
    - Disables root login over SSH
    - Sets MaxAuthTries to 3 (limits brute-force attempts)
    - Sets a 30-second login grace period

  This writes /etc/ssh/sshd_config.d/099-hardening.conf and reloads sshd.
  It requires sudo.

  IMPORTANT: Make sure your SSH public key is already in ~/.ssh/authorized_keys
  on this machine before applying — password auth will be disabled.

INFO

if confirm "  Apply SSH hardening?"; then
  HARDEN_SSH=""
  if [[ -f "$(dirname "$0")/harden-sshd.sh" ]]; then
    HARDEN_SSH="$(dirname "$0")/harden-sshd.sh"
  elif [[ -f "scripts/harden-sshd.sh" ]]; then
    HARDEN_SSH="scripts/harden-sshd.sh"
  fi

  if [[ -n "$HARDEN_SSH" ]]; then
    # first-run.sh already gatekept this step via confirm() — always pass --confirm
    sudo bash "$HARDEN_SSH" --confirm
  else
    echo "  harden-sshd.sh not found. Run manually from the mac-security repo."
  fi
else
  echo "  Skipping SSH hardening."
  echo "  Run later with: sudo bash scripts/harden-sshd.sh"
fi

# ── step 6: firewall ──────────────────────────────────────────────────────────

header "Step 6 — Application Firewall"

cat <<'INFO'
  What firewall hardening does:
    - Enables the Application Firewall (blocks unsolicited inbound connections)
    - Enables stealth mode (ignores pings, won't respond to closed-port probes)

  It does NOT enable "Block all incoming" — that setting breaks SSH.
  Use the --with-pf flag on enable-stealth-firewall.sh separately if you want
  port-level blocking via pf (allows SSH, blocks everything else inbound).

  Requires sudo.

INFO

if confirm "  Enable Application Firewall with stealth mode?"; then
  FIREWALL_SCRIPT=""
  if [[ -f "$(dirname "$0")/enable-stealth-firewall.sh" ]]; then
    FIREWALL_SCRIPT="$(dirname "$0")/enable-stealth-firewall.sh"
  elif [[ -f "scripts/enable-stealth-firewall.sh" ]]; then
    FIREWALL_SCRIPT="scripts/enable-stealth-firewall.sh"
  fi

  if [[ -n "$FIREWALL_SCRIPT" ]]; then
    # first-run.sh already gatekept this step via confirm() — always pass --confirm
    sudo bash "$FIREWALL_SCRIPT" --confirm
  else
    echo "  enable-stealth-firewall.sh not found. Run manually from the mac-security repo."
  fi
else
  echo "  Skipping firewall hardening."
  echo "  Run later with: sudo bash scripts/enable-stealth-firewall.sh"
fi

# ── step 7: final audit ───────────────────────────────────────────────────────

header "Step 7 — Final Audit"

echo "  Re-running the audit to verify findings are resolved..."
echo

if [[ -n "$AUDIT_CMD" ]]; then
  FINAL_OUTPUT=$(eval "$AUDIT_CMD --brief" 2>/dev/null)
  echo "$FINAL_OUTPUT" | awk '/## Findings Summary/,0'
fi

# ── done ──────────────────────────────────────────────────────────────────────

hr

cat <<'DONE'
  Bootstrap complete.

  Next steps:
    - Review the full audit:   mac-security-audit
    - Save audit to history:   mac-security-audit --save
    - Snapshot this machine:   mac-security-capture
    - Read the guides:         https://github.com/davidwhittington/mac-security/tree/main/docs/guides

  Scheduling daily audits:
    cp config/launchagents/com.mac-security.security-audit.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.mac-security.security-audit.plist

DONE
