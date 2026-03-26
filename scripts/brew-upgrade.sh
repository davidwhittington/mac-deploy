#!/usr/bin/env bash
# brew-upgrade.sh — update all Homebrew packages and log what changed
#
# What this script does:
#   1. Runs brew update to fetch the latest formula index
#   2. Captures the list of outdated packages before upgrading
#   3. Runs brew upgrade (formulae and casks)
#   4. Runs brew cleanup to remove old versions
#   5. Logs a dated summary of what changed to private/machines/<hostname>/brew-upgrades.log
#
# Usage:
#   bash scripts/brew-upgrade.sh [--dry-run] [--no-casks]
#   --dry-run    Show what would be upgraded without installing anything
#   --no-casks   Upgrade formulae only, skip casks

set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

DRY_RUN=false
NO_CASKS=false
CONFIRM=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]]  && DRY_RUN=true
  [[ "$arg" == "--no-casks" ]] && NO_CASKS=true
  [[ "$arg" == "--confirm" ]]  && CONFIRM=true
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "brew-upgrade.sh — update all Homebrew packages and log what changed"
    echo
    echo "Usage:"
    echo "  bash scripts/brew-upgrade.sh [--dry-run] [--no-casks] [--confirm]"
    echo
    echo "Flags:"
    echo "  --dry-run    Show what would be upgraded without installing anything"
    echo "  --no-casks   Upgrade formulae only, skip casks"
    echo "  --confirm    Skip the interactive confirmation prompt"
    echo "  --help       Show this help and exit"
    exit 0
  fi
done

# ── helpers ───────────────────────────────────────────────────────────────────

require_confirm() {
  $CONFIRM && return
  $DRY_RUN && return
  printf "  Type AGREE to continue or Ctrl+C to abort: "
  read -r _CONFIRM_REPLY
  [[ "$_CONFIRM_REPLY" == "AGREE" ]] || { echo "Aborted."; exit 0; }
}

# ── paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HOSTNAME=$(hostname -s)
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)
LOG_DIR="$REPO_ROOT/private/machines/$HOSTNAME"
LOG_FILE="$LOG_DIR/brew-upgrades.log"

# ── checks ────────────────────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
  echo "Error: Homebrew not found." >&2
  exit 1
fi

# ── header ────────────────────────────────────────────────────────────────────

echo
echo "=== Homebrew Upgrade ==="
echo
echo "Machine:  $HOSTNAME"
echo "Date:     $DATE"
$DRY_RUN && echo "Mode:     DRY RUN — no packages will be installed"
echo

# ── update index ──────────────────────────────────────────────────────────────

echo "==> Updating Homebrew formula index..."
brew update --quiet
echo "    Done."
echo

# ── capture outdated list ─────────────────────────────────────────────────────

echo "==> Checking for outdated packages..."
OUTDATED_FORMULAE=$(brew outdated --formula 2>/dev/null || true)
OUTDATED_CASKS=$(brew outdated --cask 2>/dev/null || true)

if [[ -z "$OUTDATED_FORMULAE" && -z "$OUTDATED_CASKS" ]]; then
  echo "    All packages are up to date."
  echo
  if ! $DRY_RUN && [[ -d "$LOG_DIR" ]]; then
    printf '\n## %s\n\nAll packages up to date.\n' "$TIMESTAMP" >> "$LOG_FILE"
  fi
  exit 0
fi

if [[ -n "$OUTDATED_FORMULAE" ]]; then
  echo "    Outdated formulae:"
  echo "$OUTDATED_FORMULAE" | sed 's/^/      /'
fi
if [[ -n "$OUTDATED_CASKS" ]] && ! $NO_CASKS; then
  echo "    Outdated casks:"
  echo "$OUTDATED_CASKS" | sed 's/^/      /'
fi
echo

echo "This script will:"
echo "  - Upgrades all outdated Homebrew packages listed above."
echo

require_confirm

# ── dry run exit ──────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo "==> Dry run — no changes made."
  echo "    Remove --dry-run to install upgrades."
  exit 0
fi

# ── upgrade ───────────────────────────────────────────────────────────────────

echo "==> Upgrading formulae..."
UPGRADE_OUTPUT=$(brew upgrade --formula 2>&1 || true)
echo "$UPGRADE_OUTPUT" | tail -10
echo

if ! $NO_CASKS; then
  echo "==> Upgrading casks..."
  CASK_OUTPUT=$(brew upgrade --cask --greedy 2>&1 || true)
  echo "$CASK_OUTPUT" | tail -10
  echo
fi

# ── cleanup ───────────────────────────────────────────────────────────────────

echo "==> Cleaning up old versions..."
brew cleanup --quiet 2>/dev/null || true
echo "    Done."
echo

# ── log to private submodule ──────────────────────────────────────────────────

if [[ -d "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"

  {
    printf '\n## %s\n\n' "$TIMESTAMP"

    if [[ -n "$OUTDATED_FORMULAE" ]]; then
      printf '### Formulae upgraded\n\n```\n%s\n```\n\n' "$OUTDATED_FORMULAE"
    fi

    if [[ -n "$OUTDATED_CASKS" ]] && ! $NO_CASKS; then
      printf '### Casks upgraded\n\n```\n%s\n```\n\n' "$OUTDATED_CASKS"
    fi
  } >> "$LOG_FILE"

  echo "==> Logged to: $LOG_FILE"
else
  echo "Note: private submodule not found — skipping upgrade log."
  echo "      Initialize with: git submodule update --init"
fi

echo
echo "Done. Run the security audit to verify nothing unexpected changed:"
echo "  bash scripts/audit/security-audit.sh --brief"
echo
