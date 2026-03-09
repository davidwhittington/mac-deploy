#!/usr/bin/env bash
# capture.sh — snapshot current workstation's packages and shell config
# Saves to private/machines/<hostname>/  (private submodule)
# Usage: bash pkgs/capture.sh [--zsh-only | --brew-only]

set -euo pipefail

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    echo "capture.sh — snapshot current workstation's packages and shell config"
    echo
    echo "Usage:"
    echo "  bash pkgs/capture.sh [--zsh-only | --brew-only]"
    echo
    echo "Flags:"
    echo "  --zsh-only    Capture shell config files only"
    echo "  --brew-only   Capture Homebrew packages only"
    echo "  --help        Show this help and exit"
    exit 0
  fi
done

MODE="${1:-all}"
HOSTNAME=$(hostname -s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILE_DIR="$REPO_ROOT/private/machines/$HOSTNAME"
DATE=$(date +%Y-%m-%d)

echo "==> Capturing workstation profile for: $HOSTNAME"
echo "==> Output directory: $PROFILE_DIR"
echo

mkdir -p "$PROFILE_DIR"

# ── Homebrew ──────────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" || "$MODE" == "--brew-only" ]]; then
  if command -v brew &>/dev/null; then
    echo "--> Saving Brewfile..."
    brew bundle dump --file="$PROFILE_DIR/Brewfile" --force
    echo "    Saved: $PROFILE_DIR/Brewfile"

    echo "--> Saving formula list..."
    brew list --formula > "$PROFILE_DIR/brew-formulae.txt"

    echo "--> Saving cask list..."
    brew list --cask > "$PROFILE_DIR/brew-casks.txt"

    echo "--> Saving tap list..."
    brew tap > "$PROFILE_DIR/brew-taps.txt"
    echo
  else
    echo "    [skip] Homebrew not installed"
  fi
fi

# ── Shell Config ──────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" || "$MODE" == "--zsh-only" ]]; then
  echo "--> Saving shell configuration..."
  mkdir -p "$PROFILE_DIR/shell"

  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.zsh_aliases ~/.zsh_functions ~/.zsh_local; do
    if [[ -f "$f" ]]; then
      cp "$f" "$PROFILE_DIR/shell/$(basename "$f")"
      echo "    Saved: $(basename "$f")"
    fi
  done

  # Oh My Zsh / Prezto / Starship detection
  if [[ -d ~/.oh-my-zsh ]]; then
    echo "--> Oh My Zsh detected"
    echo "oh-my-zsh" > "$PROFILE_DIR/shell/zsh-framework.txt"
    # Save custom plugins/themes list
    grep "plugins=" ~/.zshrc 2>/dev/null > "$PROFILE_DIR/shell/omz-plugins.txt" || true
    grep "ZSH_THEME=" ~/.zshrc 2>/dev/null > "$PROFILE_DIR/shell/omz-theme.txt" || true
  elif [[ -f ~/.zpreztorc ]]; then
    echo "--> Prezto detected"
    echo "prezto" > "$PROFILE_DIR/shell/zsh-framework.txt"
    cp ~/.zpreztorc "$PROFILE_DIR/shell/.zpreztorc"
  fi

  # Starship
  if command -v starship &>/dev/null; then
    echo "--> Starship detected"
    [[ -f ~/.config/starship.toml ]] && cp ~/.config/starship.toml "$PROFILE_DIR/shell/starship.toml"
  fi
  echo
fi

# ── Git Config ────────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" ]]; then
  echo "--> Saving git config..."
  git config --global --list > "$PROFILE_DIR/git-config-global.txt" 2>/dev/null || true

  # Save .gitconfig (redact credentials)
  if [[ -f ~/.gitconfig ]]; then
    grep -v "token\|password\|secret" ~/.gitconfig > "$PROFILE_DIR/gitconfig" || true
    echo "    Saved: gitconfig (credentials redacted)"
  fi
  echo
fi

# ── SSH Keys (list only, never copy keys) ─────────────────────────────────────

if [[ "$MODE" == "all" ]]; then
  echo "--> Listing SSH keys (names only, keys not copied)..."
  ls ~/.ssh/*.pub 2>/dev/null | xargs -I{} basename {} > "$PROFILE_DIR/ssh-pubkeys-list.txt" || echo "(none)" > "$PROFILE_DIR/ssh-pubkeys-list.txt"
  cat "$PROFILE_DIR/ssh-pubkeys-list.txt"
  echo
fi

# ── macOS Defaults ────────────────────────────────────────────────────────────

if [[ "$MODE" == "all" ]]; then
  echo "--> Exporting common macOS defaults..."
  mkdir -p "$PROFILE_DIR/defaults"

  # Dock
  defaults export com.apple.dock - > "$PROFILE_DIR/defaults/dock.plist" 2>/dev/null || true
  # Finder
  defaults export com.apple.finder - > "$PROFILE_DIR/defaults/finder.plist" 2>/dev/null || true
  # Keyboard
  defaults export NSGlobalDomain - > "$PROFILE_DIR/defaults/global.plist" 2>/dev/null || true
  echo "    Saved: dock, finder, global defaults"
  echo
fi

# ── Manifest ──────────────────────────────────────────────────────────────────

cat > "$PROFILE_DIR/MANIFEST.md" <<EOF
# Profile: $HOSTNAME

Captured: $DATE
macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))
Architecture: $(uname -m)

## Files
$(ls -1 "$PROFILE_DIR" | grep -v MANIFEST)
EOF

echo "==> Capture complete: $PROFILE_DIR"
echo "==> Manifest: $PROFILE_DIR/MANIFEST.md"
