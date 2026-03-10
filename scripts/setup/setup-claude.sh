#!/usr/bin/env bash
# setup-claude.sh — install and configure Claude Code on a new Mac
#
# What this does:
#   1. Installs Claude Code via Homebrew cask (if not already installed)
#   2. Creates ~/.claude/ directory structure
#   3. Deploys settings.json (from template, with CLAUDE_DEFAULT_MODE set)
#   4. Lets you pick a status line style from the gallery (or keep default)
#   5. Deploys ~/.claude/CLAUDE.md if one does not already exist
#   6. Installs project-management scripts and issue templates
#
# Usage:
#   bash scripts/setup/setup-claude.sh [--auto] [--statusline <name>]
#
# Options:
#   --auto                    Skip all prompts, use defaults
#   --statusline <name>       Choose status line variant: default | minimal | verbose
#   --skip-install            Skip the brew install step (Claude already installed)
#   --help                    Show this help and exit

set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

AUTO=false
SKIP_INSTALL=false
STATUSLINE_CHOICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)              AUTO=true ;;
    --skip-install)      SKIP_INSTALL=true ;;
    --statusline)        STATUSLINE_CHOICE="$2"; shift ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES="$REPO_ROOT/configs/templates/claude"
CLAUDE_DIR="$HOME/.claude"

# ── helpers ───────────────────────────────────────────────────────────────────

hr()     { echo; echo "────────────────────────────────────────────────────"; echo; }
header() { hr; echo "  $1"; hr; }
ok()     { echo "  ✓ $1"; }
info()   { echo "  · $1"; }
warn()   { echo "  ! $1"; }

confirm() {
  $AUTO && { echo "  $1 [auto: yes]"; return 0; }
  printf "  %s [y/N] " "$1"
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

pick_statusline() {
  if [[ -n "$STATUSLINE_CHOICE" ]]; then
    echo "$STATUSLINE_CHOICE"
    return
  fi
  if $AUTO; then
    echo "default"
    return
  fi

  echo
  echo "  Status line styles:"
  echo "    1) default  — dir, git branch, model, context %"
  echo "    2) minimal  — dir and git branch only"
  echo "    3) verbose  — dir, git branch+dirty flag, model, context %, clock"
  echo
  printf "  Choose [1/2/3, default=1]: "
  read -r PICK
  case "$PICK" in
    2) echo "minimal" ;;
    3) echo "verbose" ;;
    *) echo "default" ;;
  esac
}

# ── header ────────────────────────────────────────────────────────────────────

clear
cat <<'BANNER'

  ╔══════════════════════════════════════════════════════╗
  ║              Claude Code — mac-deploy setup           ║
  ╚══════════════════════════════════════════════════════╝

  This script will:
    1. Install Claude Code (brew cask)
    2. Create ~/.claude/ directory structure
    3. Deploy settings.json with status line configured
    4. Let you pick a status line style
    5. Deploy ~/.claude/CLAUDE.md (first install only)
    6. Install project-management scripts

BANNER

if ! confirm "Ready to begin?"; then
  echo "  Aborted."
  exit 0
fi

# ── step 1: install claude ────────────────────────────────────────────────────

header "Step 1 — Claude Code"

if $SKIP_INSTALL; then
  info "Skipping install (--skip-install)."
elif command -v claude &>/dev/null; then
  ok "Claude Code is already installed: $(claude --version 2>/dev/null || echo 'installed')"
else
  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Install Homebrew first: https://brew.sh"
    warn "Then re-run this script, or install Claude manually from https://claude.ai/download"
    exit 1
  fi

  if confirm "Install Claude Code via Homebrew cask?"; then
    brew install --cask claude
    ok "Claude Code installed."
  else
    warn "Skipping install. You can install later with: brew install --cask claude"
  fi
fi

# ── step 2: directory structure ───────────────────────────────────────────────

header "Step 2 — Directory Structure"

mkdir -p "$CLAUDE_DIR"
ok "~/.claude/ exists"

# Gallery directory for reference variants
mkdir -p "$CLAUDE_DIR/gallery/statuslines"
ok "~/.claude/gallery/statuslines/ created"

# Copy gallery variants for future reference (never overwrites active config)
for variant in "$TEMPLATES/gallery/statuslines/"*.sh; do
  name=$(basename "$variant")
  dest="$CLAUDE_DIR/gallery/statuslines/$name"
  if [[ ! -f "$dest" ]]; then
    cp "$variant" "$dest"
    chmod +x "$dest"
    info "Gallery: $name"
  fi
done

# ── step 3: status line ───────────────────────────────────────────────────────

header "Step 3 — Status Line"

STYLE=$(pick_statusline)
ok "Selected style: $STYLE"

case "$STYLE" in
  minimal) SL_SRC="$CLAUDE_DIR/gallery/statuslines/minimal.sh" ;;
  verbose) SL_SRC="$CLAUDE_DIR/gallery/statuslines/verbose.sh" ;;
  *)       SL_SRC="$TEMPLATES/statusline-command.sh" ;;
esac

cp "$SL_SRC" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "~/.claude/statusline-command.sh deployed ($STYLE)"

# ── step 4: settings.json ─────────────────────────────────────────────────────

header "Step 4 — Settings"

# Accepts env override: CLAUDE_DEFAULT_MODE=plan bash setup-claude.sh
# Valid values: acceptEdits (default), auto, plan
CLAUDE_DEFAULT_MODE="${CLAUDE_DEFAULT_MODE:-acceptEdits}"
export CLAUDE_DEFAULT_MODE HOME

SETTINGS_TMPL="$TEMPLATES/settings.json.tmpl"
SETTINGS_DEST="$CLAUDE_DIR/settings.json"

rendered=""
if command -v envsubst &>/dev/null; then
  rendered=$(envsubst < "$SETTINGS_TMPL")
elif command -v python3 &>/dev/null; then
  rendered=$(python3 -c "
import os, re, sys
def sub(m): return os.environ.get(m.group(1), m.group(0))
content = open('$SETTINGS_TMPL').read()
print(re.sub(r'\\\$\{([A-Za-z_][A-Za-z0-9_]*)\}', sub, content), end='')
")
else
  warn "envsubst and python3 not found — copying template as-is. Edit manually."
  rendered=$(cat "$SETTINGS_TMPL")
fi

if [[ -f "$SETTINGS_DEST" ]]; then
  BACKUP="$SETTINGS_DEST.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS_DEST" "$BACKUP"
  info "Backed up existing settings.json → $BACKUP"
fi

printf '%s\n' "$rendered" > "$SETTINGS_DEST"
ok "~/.claude/settings.json deployed"
info "Status line command: bash ~/.claude/statusline-command.sh"
info "Default mode: $CLAUDE_DEFAULT_MODE"
info "To add hooks, edit ~/.claude/settings.json and add a 'hooks' block."

# ── step 5: CLAUDE.md ─────────────────────────────────────────────────────────

header "Step 5 — Global Instructions (CLAUDE.md)"

CLAUDE_MD_DEST="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_MD_TMPL="$TEMPLATES/CLAUDE.md.tmpl"

if [[ -f "$CLAUDE_MD_DEST" ]]; then
  ok "~/.claude/CLAUDE.md already exists — leaving untouched."
  info "Review the template at: $CLAUDE_MD_TMPL"
else
  GIT_USER_NAME="${GIT_USER_NAME:-Your Name}"
  GIT_NOREPLY_EMAIL="${GIT_NOREPLY_EMAIL:-you@users.noreply.github.com}"
  export GIT_USER_NAME GIT_NOREPLY_EMAIL

  if command -v envsubst &>/dev/null; then
    envsubst < "$CLAUDE_MD_TMPL" > "$CLAUDE_MD_DEST"
  else
    cp "$CLAUDE_MD_TMPL" "$CLAUDE_MD_DEST"
  fi
  ok "~/.claude/CLAUDE.md deployed from template."
  warn "Edit ~/.claude/CLAUDE.md to personalize your global instructions."
fi

# ── step 6: project-management ───────────────────────────────────────────────

header "Step 6 — Project Management Scripts"

PM_SRC="$REPO_ROOT/scripts/project-management"
PM_DEST="$CLAUDE_DIR/project-management"

if [[ -d "$PM_SRC" ]]; then
  if [[ -d "$PM_DEST" ]]; then
    ok "~/.claude/project-management/ already exists — leaving untouched."
  else
    cp -r "$PM_SRC" "$PM_DEST"
    chmod +x "$PM_DEST/setup.sh" 2>/dev/null || true
    ok "~/.claude/project-management/ installed."
  fi
else
  info "No project-management scripts found in this repo — skipping."
  info "To install separately, see: https://github.com/davidwhittington/mac-deploy"
fi

# ── done ──────────────────────────────────────────────────────────────────────

hr

cat <<'DONE'
  Claude Code setup complete.

  Next steps:
    - Open a new Claude Code session — the status line will appear immediately.
    - Edit ~/.claude/CLAUDE.md to add your own global instructions.
    - To switch status line styles:
        cp ~/.claude/gallery/statuslines/minimal.sh ~/.claude/statusline-command.sh
        cp ~/.claude/gallery/statuslines/verbose.sh ~/.claude/statusline-command.sh
    - To add hooks (session tracking, notifications):
        See the hooks section in ~/.claude/settings.json
    - To run project management setup in a repo:
        bash ~/.claude/project-management/setup.sh

DONE
