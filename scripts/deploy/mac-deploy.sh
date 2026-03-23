#!/usr/bin/env bash
# mac-deploy.sh — bootstrap a new Mac from factory state to fleet-ready
#
# Installs Homebrew, core packages, shell config, Starship, Nerd Fonts,
# tmux, iTerm2 shell integration, git performance settings, SSH key,
# Claude Code, and security baseline.
#
# Usage:
#   curl -fsSL <raw-url> | bash                     # remote bootstrap
#   bash scripts/deploy/mac-deploy.sh               # from repo clone
#   bash scripts/deploy/mac-deploy.sh --minimal     # core only, skip extras
#   bash scripts/deploy/mac-deploy.sh --dry-run     # show what would happen
#
# Options:
#   --minimal     Install core packages only (skip tools, fun, casks)
#   --dry-run     Print actions without executing
#   --skip-brew   Skip Homebrew install (already installed)
#   --hostname X  Set machine hostname
#   --help        Show this help

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

MINIMAL=false
DRY_RUN=false
SKIP_BREW=false
SET_HOSTNAME=""

# Taps
TAPS=(
  davidwhittington/mac-security
  peonping/tap
)

# Core packages (install everywhere)
CORE_FORMULAE=(
  antidote
  direnv
  git
  gh
  git-crypt
  gnupg
  mac-security
  node
  peon-ping
  pinentry-mac
  starship
  tmux
)

# Tools (install as needed)
TOOL_FORMULAE=(
  ansible
  btop
  dos2unix
  fastfetch
  git-filter-repo
  go
  htop
  httping
  midnight-commander
  minicom
  nmap
  p7zip
  python@3.13
  screen
  sshpass
  supabase
  tcpdump
  telnet
  terraform
  tree
  watch
  wget
)

# Fun / optional
FUN_FORMULAE=(
  cmatrix
  cowsay
  fortune
  jp2a
  lolcat
)

# Casks
CORE_CASKS=(
  font-jetbrains-mono-nerd-font
)

TOOL_CASKS=(
  font-caskaydia-mono-nerd-font
  deskpad
)

# npm globals
NPM_GLOBALS=(
  @anthropic-ai/claude-code
  wrangler
)

# zsh plugins
ZSH_PLUGINS='getantidote/use-omz
ohmyzsh/ohmyzsh path:lib

ohmyzsh/ohmyzsh path:plugins/aliases
ohmyzsh/ohmyzsh path:plugins/common-aliases
ohmyzsh/ohmyzsh path:plugins/debian
ohmyzsh/ohmyzsh path:plugins/firewalld
ohmyzsh/ohmyzsh path:plugins/git
ohmyzsh/ohmyzsh path:plugins/history
ohmyzsh/ohmyzsh path:plugins/nvm
ohmyzsh/ohmyzsh path:plugins/podman
ohmyzsh/ohmyzsh path:plugins/sudo

ptavares/zsh-direnv
toku-sa-n/zsh-dot-up
zsh-users/zsh-syntax-highlighting kind:defer'

# ── Parse args ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --minimal)    MINIMAL=true ;;
    --dry-run)    DRY_RUN=true ;;
    --skip-brew)  SKIP_BREW=true ;;
    --hostname)   SET_HOSTNAME="$2"; shift ;;
    --help|-h)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── Helpers ───────────────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

step()  { echo -e "\n${BOLD}${BLUE}▸ $1${RESET}"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $1"; }
info()  { echo -e "  ${DIM}·${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $1"; }
fail()  { echo -e "  ${RED}✗${RESET} $1"; }

run() {
  if $DRY_RUN; then
    echo -e "  ${DIM}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

need_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo -e "\n${BOLD}Some steps require sudo. Enter your password:${RESET}"
    sudo -v
    # Keep sudo alive
    while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
  fi
}

# ── Detect environment ────────────────────────────────────────────────────────

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

echo -e "\n${BOLD}mac-deploy${RESET} — fleet workstation bootstrap"
echo -e "${DIM}Architecture: $ARCH | Prefix: $BREW_PREFIX${RESET}"
$DRY_RUN && echo -e "${YELLOW}DRY RUN — no changes will be made${RESET}"
$MINIMAL && echo -e "${YELLOW}MINIMAL — core packages only${RESET}"
echo

# ── 1. Homebrew ───────────────────────────────────────────────────────────────

step "Homebrew"

if $SKIP_BREW; then
  info "Skipping Homebrew install (--skip-brew)"
elif command -v brew &>/dev/null; then
  ok "Homebrew already installed ($(brew --version | head -1))"
else
  info "Installing Homebrew..."
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add to current session
  if [[ -f "$BREW_PREFIX/bin/brew" ]]; then
    eval "$($BREW_PREFIX/bin/brew shellenv)"
  fi
fi

# Ensure brew is in PATH for this script
if [[ -f "$BREW_PREFIX/bin/brew" ]]; then
  eval "$($BREW_PREFIX/bin/brew shellenv)"
fi

# .zprofile — ensure brew shellenv persists
if ! grep -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
  step "Adding brew shellenv to ~/.zprofile"
  run bash -c "echo 'eval \"\$($BREW_PREFIX/bin/brew shellenv)\"' >> ~/.zprofile"
  ok "~/.zprofile updated"
fi

# ── 2. Taps ───────────────────────────────────────────────────────────────────

step "Brew taps"

for tap in "${TAPS[@]}"; do
  if brew tap | grep -q "^${tap}$" 2>/dev/null; then
    ok "$tap (already tapped)"
  else
    info "Tapping $tap..."
    run brew tap "$tap"
  fi
done

# ── 3. Packages ──────────────────────────────────────────────────────────────

step "Core formulae"
for pkg in "${CORE_FORMULAE[@]}"; do
  if brew list --formula "$pkg" &>/dev/null; then
    ok "$pkg"
  else
    info "Installing $pkg..."
    run brew install "$pkg"
  fi
done

if ! $MINIMAL; then
  step "Tool formulae"
  for pkg in "${TOOL_FORMULAE[@]}"; do
    if brew list --formula "$pkg" &>/dev/null; then
      ok "$pkg"
    else
      info "Installing $pkg..."
      run brew install "$pkg"
    fi
  done

  step "Fun formulae"
  for pkg in "${FUN_FORMULAE[@]}"; do
    if brew list --formula "$pkg" &>/dev/null; then
      ok "$pkg"
    else
      info "Installing $pkg..."
      run brew install "$pkg"
    fi
  done
fi

# ── 4. Casks ─────────────────────────────────────────────────────────────────

step "Core casks"
for cask in "${CORE_CASKS[@]}"; do
  if brew list --cask "$cask" &>/dev/null; then
    ok "$cask"
  else
    info "Installing $cask..."
    run brew install --cask "$cask"
  fi
done

if ! $MINIMAL; then
  step "Tool casks"
  for cask in "${TOOL_CASKS[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
      ok "$cask"
    else
      info "Installing $cask..."
      run brew install --cask "$cask"
    fi
  done
fi

# ── 5. npm globals ───────────────────────────────────────────────────────────

step "npm globals"
for pkg in "${NPM_GLOBALS[@]}"; do
  short_name=$(echo "$pkg" | sed 's|.*/||')
  if npm list -g "$pkg" &>/dev/null 2>&1; then
    ok "$short_name"
  else
    info "Installing $pkg..."
    run npm install -g "$pkg"
  fi
done

# ── 6. Shell config ──────────────────────────────────────────────────────────

step "zsh plugins"
PLUGINS_FILE="${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
if [[ -f "$PLUGINS_FILE" ]]; then
  ok ".zsh_plugins.txt exists"
else
  info "Writing .zsh_plugins.txt..."
  if ! $DRY_RUN; then
    echo "$ZSH_PLUGINS" > "$PLUGINS_FILE"
  fi
  ok ".zsh_plugins.txt created"
fi

step "~/.zshrc"
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  warn ".zshrc already exists — checking for required entries"

  needs_update=false

  if ! grep -q 'starship init zsh' "$ZSHRC" 2>/dev/null; then
    warn "Missing: starship init"
    needs_update=true
  fi
  if ! grep -q 'iterm2_shell_integration' "$ZSHRC" 2>/dev/null; then
    warn "Missing: iTerm2 shell integration"
    needs_update=true
  fi
  if ! grep -q 'antidote' "$ZSHRC" 2>/dev/null; then
    warn "Missing: antidote"
    needs_update=true
  fi
  if ! grep -q 'direnv hook' "$ZSHRC" 2>/dev/null; then
    warn "Missing: direnv"
    needs_update=true
  fi
  if ! grep -q 'tmux -CC' "$ZSHRC" 2>/dev/null; then
    warn "Missing: tmux auto-launch"
    needs_update=true
  fi

  if $needs_update; then
    warn "Review .zshrc and add missing entries (see deployment guide)"
  else
    ok ".zshrc has all required entries"
  fi
else
  info "Writing .zshrc..."
  if ! $DRY_RUN; then
    cat > "$ZSHRC" << 'ZSHRC_CONTENT'
eval "$(starship init zsh)"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

source $(brew --prefix)/opt/antidote/share/antidote/antidote.zsh
antidote load

export PATH="$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)

# direnv
eval "$(direnv hook zsh)"

# Auto-launch tmux in iTerm2 control mode (native tabs/splits)
# -CC = control mode; -A = attach if exists; -s main = session name
if [[ -z "$TMUX" && "$TERM_PROGRAM" == "iTerm.app" && -z "$INSIDE_EMACS" && -z "$VSCODE_PID" ]]; then
  tmux -CC new-session -A -s main
fi
ZSHRC_CONTENT
  fi
  ok ".zshrc created"
fi

# ── 7. iTerm2 shell integration ──────────────────────────────────────────────

step "iTerm2 shell integration"
ITERM_INT="$HOME/.iterm2_shell_integration.zsh"
if [[ -f "$ITERM_INT" ]]; then
  ok "Already installed"
else
  info "Downloading..."
  run curl -fsSL https://iterm2.com/shell_integration/zsh -o "$ITERM_INT"
  run chmod +x "$ITERM_INT"
  ok "Installed"
fi

# ── 8. iTerm2 font ───────────────────────────────────────────────────────────

step "iTerm2 font configuration"
ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
if [[ -f "$ITERM_PLIST" ]]; then
  CURRENT_FONT=$(/usr/libexec/PlistBuddy -c "Print ':New Bookmarks:0:Normal Font'" "$ITERM_PLIST" 2>/dev/null || echo "unknown")
  if [[ "$CURRENT_FONT" == "JetBrainsMonoNFM-Regular 18" ]]; then
    ok "Font already set to JetBrainsMonoNFM-Regular 18"
  else
    info "Setting font to JetBrainsMonoNFM-Regular 18 (was: $CURRENT_FONT)"
    run /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'JetBrainsMonoNFM-Regular 18'" "$ITERM_PLIST"
    ok "Font updated (restart iTerm2 to apply)"
  fi
else
  warn "iTerm2 plist not found — install iTerm2 first, then re-run"
fi

# ── 9. Starship config ───────────────────────────────────────────────────────

step "Starship config"
STARSHIP_CONF="$HOME/.config/starship.toml"
if [[ -f "$STARSHIP_CONF" ]]; then
  if grep -q 'command_timeout' "$STARSHIP_CONF" 2>/dev/null; then
    ok "Starship config exists with command_timeout set"
  else
    info "Adding command_timeout to existing config..."
    run sed -i '' 's/^add_newline = true$/add_newline = true\ncommand_timeout = 2000/' "$STARSHIP_CONF"
    ok "command_timeout added"
  fi

  if grep -q '\[hostname\]' "$STARSHIP_CONF" 2>/dev/null; then
    ok "Hostname module configured"
  else
    info "Adding hostname module..."
    if ! $DRY_RUN; then
      cat >> "$STARSHIP_CONF" << 'STARSHIP_HOST'

[hostname]
ssh_only = false
format = "[$emoji$hostname]($style) "
style = "bold dimmed green"
STARSHIP_HOST
    fi
    ok "Hostname module added"
  fi
else
  warn "No starship.toml found — copy from an existing fleet machine:"
  info "scp macbook-pro:~/.config/starship.toml ~/.config/starship.toml"
fi

# ── 10. tmux ──────────────────────────────────────────────────────────────────

step "tmux config"
TMUX_CONF="$HOME/.tmux.conf"
if [[ -f "$TMUX_CONF" ]]; then
  ok ".tmux.conf exists"
else
  warn "No .tmux.conf found — copy from an existing fleet machine:"
  info "scp macbook-pro:~/.tmux.conf ~/.tmux.conf"
fi

run mkdir -p ~/Documents/logs
ok "~/Documents/logs/ exists (iCloud session logging)"

# ── 11. Git ───────────────────────────────────────────────────────────────────

step "Git performance settings"

for setting in "core.untrackedCache:true" "core.fsmonitor:true" "feature.manyFiles:true"; do
  key="${setting%%:*}"
  val="${setting##*:}"
  current=$(git config --global "$key" 2>/dev/null || echo "")
  if [[ "$current" == "$val" ]]; then
    ok "$key = $val"
  else
    run git config --global "$key" "$val"
    ok "$key = $val (set)"
  fi
done

# ── 12. SSH key ───────────────────────────────────────────────────────────────

step "SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
  ok "ed25519 key exists"
  info "Fingerprint: $(ssh-keygen -lf "$SSH_KEY" 2>/dev/null | awk '{print $2}')"
else
  info "Generating ed25519 key..."
  run mkdir -p ~/.ssh
  run chmod 700 ~/.ssh
  run ssh-keygen -t ed25519 -C "david@$(hostname -s)" -f "$SSH_KEY" -N ""
  ok "Key generated"
fi

# SSH config
step "SSH config"
SSH_CONF="$HOME/.ssh/config"
if [[ -f "$SSH_CONF" ]]; then
  ok "~/.ssh/config exists"
  # Check for fleet entries
  for host in macbook-pro macbook-air mac-pro; do
    if grep -qi "Host $host" "$SSH_CONF" 2>/dev/null; then
      ok "$host entry found"
    else
      warn "$host entry missing — add it manually or copy from fleet"
    fi
  done
else
  info "Writing SSH config with fleet hosts..."
  if ! $DRY_RUN; then
    mkdir -p ~/.ssh
    cat > "$SSH_CONF" << 'SSH_CONFIG'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
  IdentityFile ~/.ssh/id_rsa

Host macbook-pro
    HostName 192.168.6.0
    User david

Host macbook-air
    HostName 192.168.6.177
    User david

Host mac-pro
    HostName 192.168.5.67
    User david
SSH_CONFIG
    chmod 600 "$SSH_CONF"
  fi
  ok "SSH config created with fleet hosts"
fi

# ── 13. Hostname ──────────────────────────────────────────────────────────────

step "Hostname"
CURRENT_HOSTNAME=$(hostname -s)
if [[ -n "$SET_HOSTNAME" ]]; then
  if [[ "$CURRENT_HOSTNAME" == "$SET_HOSTNAME" ]]; then
    ok "Hostname already set to $SET_HOSTNAME"
  else
    info "Setting hostname to $SET_HOSTNAME (currently: $CURRENT_HOSTNAME)..."
    need_sudo
    run sudo scutil --set HostName "$SET_HOSTNAME"
    run sudo scutil --set LocalHostName "$SET_HOSTNAME"
    run sudo scutil --set ComputerName "$SET_HOSTNAME"
    ok "Hostname set to $SET_HOSTNAME"
  fi
else
  info "Current hostname: $CURRENT_HOSTNAME"
  info "Use --hostname <name> to set it"
fi

# ── 14. Security baseline ────────────────────────────────────────────────────

step "Security baseline"

# Check if mac-security-audit is available
if command -v mac-security-audit &>/dev/null; then
  ok "mac-security-audit is installed"
  info "Run 'mac-security-audit --brief' to check posture"
else
  warn "mac-security-audit not in PATH — check brew installation"
fi

# Check key security settings (non-destructive, no sudo needed)
if fdesetup status 2>/dev/null | grep -q "On"; then
  ok "FileVault is enabled"
else
  fail "FileVault is OFF — enable in System Settings > Privacy & Security"
fi

if csrutil status 2>/dev/null | grep -q "enabled"; then
  ok "SIP is enabled"
else
  fail "SIP is disabled"
fi

if spctl --status 2>/dev/null | grep -q "enabled"; then
  ok "Gatekeeper is enabled"
else
  fail "Gatekeeper is disabled"
fi

FW_STATE=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "unknown")
if echo "$FW_STATE" | grep -q "enabled"; then
  ok "Application Firewall is enabled"
else
  warn "Application Firewall may be off — check System Settings"
fi

echo
info "For full hardening (SSH, stealth firewall), run with sudo:"
info "  sudo bash scripts/deploy/mac-deploy.sh --harden"

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo -e "${BOLD}────────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}  mac-deploy complete${RESET}"
echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
echo
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  1. Restart iTerm2 to pick up font and shell changes"
echo -e "  2. Copy starship.toml from fleet: ${GREEN}scp macbook-pro:~/.config/starship.toml ~/.config/${RESET}"
echo -e "  3. Copy tmux.conf from fleet:     ${GREEN}scp macbook-pro:~/.tmux.conf ~/${RESET}"
echo -e "  4. Distribute SSH key to fleet:   ${GREEN}ssh-copy-id macbook-pro${RESET}"
echo -e "  5. Run security audit:            ${GREEN}mac-security-audit --brief${RESET}"
echo
