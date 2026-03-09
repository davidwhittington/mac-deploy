#!/usr/bin/env bash
# deploy.sh — deploy a saved workstation profile to the current machine
# Usage: bash pkgs/deploy.sh <profile-hostname> [--dry-run] [--zsh-only | --brew-only]
#
# The profile should exist in pkgs/machines/<profile-hostname>/

set -euo pipefail

PROFILE_HOST="${1:-}"
MODE="${2:-all}"
DRY_RUN=false
CONFIRM=false

# Flag parsing
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]]  && DRY_RUN=true
  [[ "$arg" == "--zsh-only" ]] && MODE="--zsh-only"
  [[ "$arg" == "--brew-only" ]] && MODE="--brew-only"
  [[ "$arg" == "--confirm" ]]  && CONFIRM=true
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "deploy.sh — deploy a saved workstation profile to the current machine"
    echo
    echo "Usage:"
    echo "  bash pkgs/deploy.sh <profile-hostname> [--dry-run] [--confirm] [--zsh-only | --brew-only]"
    echo
    echo "Flags:"
    echo "  --dry-run     Show what would be done without making changes"
    echo "  --zsh-only    Restore shell config files only"
    echo "  --brew-only   Restore Homebrew packages only"
    echo "  --confirm     Skip the interactive confirmation prompt"
    echo "  --help        Show this help and exit"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/machines/$PROFILE_HOST"

if [[ -z "$PROFILE_HOST" ]]; then
  echo "Usage: bash pkgs/deploy.sh <profile-hostname> [--dry-run] [--zsh-only|--brew-only]"
  echo
  echo "Available profiles:"
  ls "$SCRIPT_DIR/machines/" 2>/dev/null || echo "  (none captured yet)"
  exit 1
fi

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "ERROR: Profile not found: $PROFILE_DIR"
  echo
  echo "Available profiles:"
  ls "$SCRIPT_DIR/machines/" 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "==> Deploying profile from: $PROFILE_HOST"
echo "==> Profile directory: $PROFILE_DIR"
$DRY_RUN && echo "==> DRY RUN — no changes will be made"
echo

echo "This script will:"
echo "  - Restores Homebrew packages and overwrites shell config (~/.zshrc, ~/.zprofile, etc.) and ~/.gitconfig. Existing files will be backed up."
echo

require_confirm

run() {
  # run <description> <command...>
  local desc="$1"; shift
  if $DRY_RUN; then
    echo "    [DRY RUN] $desc: $*"
  else
    echo "--> $desc"
    eval "$@"
  fi
}

# ── Xcode CLT ─────────────────────────────────────────────────────────────────

if ! xcode-select -p &>/dev/null; then
  echo "--> Installing Xcode Command Line Tools..."
  $DRY_RUN || xcode-select --install
  echo "    Follow the installer prompt, then re-run this script."
  exit 0
fi

# ── Homebrew ──────────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" || "$MODE" == "--brew-only" ]]; then
  if ! command -v brew &>/dev/null; then
    echo "--> Installing Homebrew..."
    $DRY_RUN || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  BREWFILE="$PROFILE_DIR/Brewfile"
  if [[ -f "$BREWFILE" ]]; then
    echo "--> Restoring Homebrew packages from Brewfile..."
    $DRY_RUN && { echo "    [DRY RUN] brew bundle install --file=$BREWFILE"; } || brew bundle install --file="$BREWFILE" --no-lock
  else
    echo "    [skip] No Brewfile found in profile"
  fi
  echo
fi

# ── Shell Config ──────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" || "$MODE" == "--zsh-only" ]]; then
  SHELL_DIR="$PROFILE_DIR/shell"
  if [[ -d "$SHELL_DIR" ]]; then
    echo "--> Restoring shell configuration..."

    for f in .zshrc .zshenv .zprofile .zsh_aliases .zsh_functions; do
      src="$SHELL_DIR/$f"
      dst="$HOME/$f"
      if [[ -f "$src" ]]; then
        if [[ -f "$dst" ]] && ! $DRY_RUN; then
          cp "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)"
          echo "    Backed up: $dst"
        fi
        run "Installing $f" cp "$src" "$dst"
      fi
    done

    # Starship
    if [[ -f "$SHELL_DIR/starship.toml" ]]; then
      mkdir -p ~/.config
      run "Installing starship.toml" cp "$SHELL_DIR/starship.toml" ~/.config/starship.toml
    fi

    echo
  else
    echo "    [skip] No shell directory in profile"
  fi
fi

# ── Git Config ────────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" ]]; then
  GITCFG="$PROFILE_DIR/gitconfig"
  if [[ -f "$GITCFG" ]]; then
    echo "--> Restoring git config..."
    if [[ -f ~/.gitconfig ]] && ! $DRY_RUN; then
      cp ~/.gitconfig ~/.gitconfig.bak.$(date +%Y%m%d%H%M%S)
    fi
    run "Installing .gitconfig" cp "$GITCFG" ~/.gitconfig
    echo "    NOTE: You may need to update [user] name/email in ~/.gitconfig"
    echo
  fi
fi

echo "==> Deploy complete."
echo
echo "Next steps:"
echo "  1. Reload shell: source ~/.zshrc"
echo "  2. Verify SSH keys are configured"
echo "  3. Run security audit: bash scripts/audit/security-audit.sh"
