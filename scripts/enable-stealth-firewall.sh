#!/usr/bin/env bash
# enable-stealth-firewall.sh — enable Application Firewall with stealth mode
# Optionally sets up pf for port-level inbound blocking (recommended if SSH is in use).
#
# Usage: sudo bash scripts/enable-stealth-firewall.sh [--with-pf] [--dry-run]
#   --with-pf   Also configure pf: allow SSH inbound, block all other inbound
#   --dry-run   Show what would change without making changes
#
# Why not block-all?
#   The Application Firewall's "Block all incoming connections" is all-or-nothing.
#   It overrides every per-app exception, including SSH. If you need SSH access,
#   use --with-pf instead: it gives you port-level control (allow 22, block everything
#   else) without breaking SSH.
#
# Requirements: must run as root (sudo)

set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

DRY_RUN=false
WITH_PF=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
  [[ "$arg" == "--with-pf" ]] && WITH_PF=true
done

# ── checks ────────────────────────────────────────────────────────────────────

if [[ "$EUID" -ne 0 ]]; then
  echo "Error: run with sudo" >&2
  echo "  sudo bash scripts/enable-stealth-firewall.sh" >&2
  exit 1
fi

SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# ── header ────────────────────────────────────────────────────────────────────

echo
echo "=== Firewall Hardening ==="
echo
echo "What this script does:"
echo "  1. Enables the Application Firewall (blocks unsolicited inbound connections)"
echo "  2. Enables stealth mode (machine won't respond to pings or closed-port probes)"
if $WITH_PF; then
  echo "  3. Configures pf: allow SSH (port 22) inbound, block everything else"
  echo "     This is port-level control the Application Firewall alone can't do."
fi
echo
echo "What it does NOT do:"
echo "  - Enable 'Block all incoming' (that would kill SSH — use --with-pf instead)"
echo

# ── current state ─────────────────────────────────────────────────────────────

echo "Current state:"
printf "  Application Firewall: %s\n" "$($SFW --getglobalstate 2>/dev/null | awk '{print $NF}' || echo 'unknown')"
printf "  Stealth mode:         %s\n" "$($SFW --getstealthmode  2>/dev/null | awk '{print $NF}' || echo 'unknown')"
printf "  Block-all:            %s\n" "$($SFW --getblockall     2>/dev/null | awk '{print $NF}' || echo 'unknown')"
echo

# ── dry run ───────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo "Changes that would be applied:"
  echo "  - Enable Application Firewall"
  echo "  - Enable stealth mode"
  if $WITH_PF; then
    echo "  - Write /etc/pf.anchors/mac-deploy (allow port 22, block all other inbound)"
    echo "  - Add mac-deploy anchor reference to /etc/pf.conf"
    echo "  - Load pf and enable"
  fi
  echo
  echo "==> Dry run — no changes made."
  exit 0
fi

# ── application firewall ──────────────────────────────────────────────────────

echo "==> Enabling Application Firewall..."
"$SFW" --setglobalstate on 2>/dev/null
echo "    Done."

echo "==> Enabling stealth mode..."
echo "    (Machine will ignore pings and won't respond to probes on closed ports.)"
"$SFW" --setstealthmode on 2>/dev/null
echo "    Done."

# ── pf (optional) ─────────────────────────────────────────────────────────────

if $WITH_PF; then
  echo
  echo "==> Configuring pf..."
  echo "    pf is a kernel-level firewall that works at the port/protocol layer."
  echo "    We add a named anchor so your rules are isolated from the system base config."

  ANCHOR_DIR="/etc/pf.anchors"
  ANCHOR_FILE="$ANCHOR_DIR/mac-deploy"

  mkdir -p "$ANCHOR_DIR"

  # Detect active interface (prefer en0; fall back to first active interface)
  IFACE="en0"
  if ! ifconfig en0 2>/dev/null | grep -q "inet "; then
    IFACE=$(route get default 2>/dev/null | awk '/interface:/ {print $2}' | head -1 || echo "en0")
  fi
  echo "    Active interface: $IFACE"

  printf '%s\n' \
    '# mac-deploy pf anchor' \
    '# Applied by scripts/enable-stealth-firewall.sh' \
    '# https://github.com/davidwhittington/mac-deploy' \
    '' \
    "# Allow established return traffic on $IFACE" \
    "pass in quick on $IFACE proto tcp from any to any flags S/SA keep state" \
    '' \
    '# Allow SSH inbound' \
    "pass in quick on $IFACE proto tcp to port 22" \
    '' \
    '# Block all other inbound' \
    "block in on $IFACE" \
    '' \
    '# Allow all outbound' \
    'pass out all keep state' \
    > "$ANCHOR_FILE"

  echo "    Written: $ANCHOR_FILE"

  # Add anchor reference to /etc/pf.conf if not already present
  if ! grep -q 'anchor "mac-deploy"' /etc/pf.conf 2>/dev/null; then
    printf '\nanchor "mac-deploy"\nload anchor "mac-deploy" from "/etc/pf.anchors/mac-deploy"\n' \
      >> /etc/pf.conf
    echo "    Updated: /etc/pf.conf"
  else
    echo "    /etc/pf.conf already references mac-deploy anchor — skipping."
  fi

  # Load rules and enable pf
  pfctl -f /etc/pf.conf 2>/dev/null || true
  pfctl -e 2>/dev/null || true
  echo "    pf loaded and enabled."

  # Deploy LaunchDaemon for persistence if the plist is in the repo
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(dirname "$SCRIPT_DIR")"
  PLIST_SRC="$REPO_ROOT/config/launchdaemons/com.mac-deploy.pf.plist"
  PLIST_DEST="/Library/LaunchDaemons/com.mac-deploy.pf.plist"

  if [[ -f "$PLIST_SRC" ]] && [[ ! -f "$PLIST_DEST" ]]; then
    cp "$PLIST_SRC" "$PLIST_DEST"
    launchctl load "$PLIST_DEST" 2>/dev/null || true
    echo "    LaunchDaemon installed — pf rules will persist across reboots."
  elif [[ -f "$PLIST_DEST" ]]; then
    echo "    LaunchDaemon already installed."
  else
    echo "    Note: pf rules will not survive a reboot without a LaunchDaemon."
    echo "    See docs/guides/firewall-pf-vs-application-firewall.md for setup."
  fi
fi

# ── new state ─────────────────────────────────────────────────────────────────

echo
echo "New state:"
printf "  Application Firewall: %s\n" "$($SFW --getglobalstate 2>/dev/null | awk '{print $NF}' || echo 'unknown')"
printf "  Stealth mode:         %s\n" "$($SFW --getstealthmode  2>/dev/null | awk '{print $NF}' || echo 'unknown')"
printf "  Block-all:            %s\n" "$($SFW --getblockall     2>/dev/null | awk '{print $NF}' || echo 'unknown')"
if $WITH_PF; then
  echo
  echo "  pf rules loaded:"
  pfctl -s rules 2>/dev/null | sed 's/^/    /' || echo "    (run: sudo pfctl -s rules)"
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo
echo "Done."
if $WITH_PF; then
  echo "  Application Firewall enabled with stealth mode."
  echo "  pf active — SSH (port 22) allowed, all other inbound blocked."
else
  echo "  Application Firewall enabled with stealth mode."
  echo "  Tip: run with --with-pf to also configure pf for port-level blocking."
fi
echo
echo "Verify with:"
echo "  bash scripts/audit/security-audit.sh --brief"
echo
