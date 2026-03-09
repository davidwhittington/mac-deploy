#!/usr/bin/env bash
# harden-sshd.sh — apply SSH hardening config to macOS sshd
# Writes /etc/ssh/sshd_config.d/099-hardening.conf and reloads sshd.
#
# Usage: sudo bash scripts/harden-sshd.sh [--dry-run]
#   --dry-run  Show what would be written without making changes
#
# Requirements: must run as root (sudo)

set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ── checks ────────────────────────────────────────────────────────────────────

if [[ "$EUID" -ne 0 ]]; then
  echo "Error: run with sudo" >&2
  echo "  sudo bash scripts/harden-sshd.sh" >&2
  exit 1
fi

CONF_DIR="/etc/ssh/sshd_config.d"
CONF_FILE="$CONF_DIR/099-hardening.conf"

# ── header ────────────────────────────────────────────────────────────────────

echo
echo "=== SSH Hardening ==="
echo

# Warn if SSH isn't currently listening
if lsof -iTCP:22 -sTCP:LISTEN -P -n 2>/dev/null | grep -q sshd; then
  SSH_ACTIVE=true
  echo "SSH is active — config will be applied and sshd reloaded."
else
  SSH_ACTIVE=false
  echo "Notice: SSH (Remote Login) is not currently active."
  echo "Config will be written — it takes effect when Remote Login is enabled."
fi
echo

# ── config content ────────────────────────────────────────────────────────────

CONF_CONTENT=$(printf '%s\n' \
  '# mac-deploy SSH hardening' \
  '# Applied by scripts/harden-sshd.sh' \
  '# https://github.com/davidwhittington/mac-deploy' \
  '' \
  'PasswordAuthentication no' \
  'PermitRootLogin no' \
  'PubkeyAuthentication yes' \
  'KbdInteractiveAuthentication no' \
  'ChallengeResponseAuthentication no' \
  'MaxAuthTries 3' \
  'LoginGraceTime 30')

echo "Config: $CONF_FILE"
echo
echo "$CONF_CONTENT"
echo

# ── dry run ───────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo "==> Dry run — no changes made."
  exit 0
fi

# ── write ─────────────────────────────────────────────────────────────────────

mkdir -p "$CONF_DIR"
printf '%s\n' "$CONF_CONTENT" > "$CONF_FILE"
echo "==> Written: $CONF_FILE"

# ── validate ──────────────────────────────────────────────────────────────────

echo "==> Validating config..."
if sshd -t 2>&1; then
  echo "    Config OK."
else
  echo
  echo "ERROR: sshd config validation failed." >&2
  echo "Check $CONF_FILE for syntax errors, then re-run." >&2
  exit 1
fi

# ── reload ────────────────────────────────────────────────────────────────────

if $SSH_ACTIVE; then
  echo "==> Reloading sshd..."
  if launchctl kickstart -k system/com.openssh.sshd 2>/dev/null; then
    echo "    sshd reloaded."
  else
    # Fallback for older macOS
    launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
    launchctl load  /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
    echo "    sshd reloaded (fallback)."
  fi
else
  echo "==> SSH not active — config will apply when Remote Login is enabled."
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo
echo "Done. Settings applied:"
echo "  PasswordAuthentication    no"
echo "  PermitRootLogin           no"
echo "  PubkeyAuthentication      yes"
echo "  KbdInteractiveAuthentication  no"
echo "  MaxAuthTries              3"
echo "  LoginGraceTime            30s"
echo
echo "Important: confirm your public key is in ~/.ssh/authorized_keys before"
echo "your next SSH session — password auth is now disabled."
echo
echo "Verify with:"
echo "  bash scripts/audit/security-audit.sh --brief"
echo
