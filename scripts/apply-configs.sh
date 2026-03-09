#!/usr/bin/env bash
# apply-configs.sh — render application config templates with per-machine settings
# and deploy them to their destination paths.
#
# How it works:
#   1. Loads base variable values from configs/settings/defaults.env
#   2. Loads per-machine overrides from private/machines/<hostname>/configs.env (if present)
#   3. For each entry in the manifest, renders the template by substituting ${VAR} placeholders
#   4. Compares rendered output to the existing destination file
#   5. Backs up the destination and writes the rendered file (or just shows a diff in --dry-run)
#
# Templates:  configs/templates/<app>/<file>.tmpl
# Settings:   configs/settings/defaults.env
#             private/machines/<hostname>/configs.env  (per-machine overrides)
# Manifest:   configs/manifests/default.conf
#
# Usage:
#   bash scripts/apply-configs.sh [options]
#
# Options:
#   --dry-run              Show what would change without writing anything
#   --list                 List available templates, current settings, and manifest entries
#   --manifest <file>      Use a custom manifest file
#   --machine <hostname>   Load settings for a specific machine (default: current hostname)
#
# Template rendering requires either:
#   envsubst  — install via: brew install gettext
#   python3   — available on any Mac with Xcode CLT (used as fallback)
#
# Per-machine settings:
#   Create private/machines/<hostname>/configs.env with KEY=VALUE overrides.
#   These are loaded on top of configs/settings/defaults.env.
#   Example:
#     GIT_USER_NAME=David Whittington
#     GIT_USER_EMAIL=david@example.com
#     SSH_KEY_PATH=~/.ssh/id_ed25519

set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

DRY_RUN=false
LIST=false
MANIFEST_ARG=""
MACHINE_NAME="$(hostname -s)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)           DRY_RUN=true ;;
    --list)              LIST=true ;;
    --manifest)          MANIFEST_ARG="$2"; shift ;;
    --machine)           MACHINE_NAME="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$REPO_ROOT/configs"
TEMPLATES_DIR="$CONFIGS_DIR/templates"
SETTINGS_FILE="$CONFIGS_DIR/settings/defaults.env"
MACHINE_SETTINGS="$REPO_ROOT/private/machines/${MACHINE_NAME}/configs.env"

[[ -n "$MANIFEST_ARG" ]] && MANIFEST="$MANIFEST_ARG" || MANIFEST="$CONFIGS_DIR/manifests/default.conf"

# ── helpers ───────────────────────────────────────────────────────────────────

load_env() {
  # load_env <file> — source KEY=VALUE pairs safely (no arbitrary shell execution)
  local file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]}"
    fi
  done < "$file"
}

render() {
  # render <template_file> — substitute ${VAR} placeholders from environment
  local tmpl="$1"

  if command -v envsubst &>/dev/null; then
    envsubst < "$tmpl"
    return
  fi

  if command -v python3 &>/dev/null; then
    local py
    py=$(mktemp /tmp/mac-security-render.XXXXXX.py)
    cat > "$py" << 'PYEOF'
import os, re, sys

def sub(m):
    return os.environ.get(m.group(1), m.group(0))

content = open(sys.argv[1]).read()
result = re.sub(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}', sub, content)
print(result, end='')
PYEOF
    python3 "$py" "$tmpl"
    rm -f "$py"
    return
  fi

  echo "ERROR: template rendering requires envsubst or python3." >&2
  echo "  Install envsubst: brew install gettext" >&2
  return 1
}

expand_dest() {
  # expand_dest <path> — expand ~ to $HOME
  local path="$1"
  echo "${path/#\~/$HOME}"
}

# ── load settings ─────────────────────────────────────────────────────────────

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "ERROR: settings file not found: $SETTINGS_FILE" >&2
  exit 1
fi

load_env "$SETTINGS_FILE"

if [[ -f "$MACHINE_SETTINGS" ]]; then
  load_env "$MACHINE_SETTINGS"
  MACHINE_SETTINGS_STATUS="loaded: $MACHINE_SETTINGS"
else
  MACHINE_SETTINGS_STATUS="not found — using defaults only"
  MACHINE_SETTINGS_STATUS+=" (create private/machines/${MACHINE_NAME}/configs.env to override)"
fi

# ── list mode ─────────────────────────────────────────────────────────────────

if $LIST; then
  echo
  echo "=== mac-security Config Templates ==="
  echo
  echo "Machine:  $MACHINE_NAME"
  echo "Manifest: $MANIFEST"
  echo "Settings: $SETTINGS_FILE"
  echo "Machine overrides: $MACHINE_SETTINGS_STATUS"
  echo

  echo "--- Available Templates ---"
  find "$TEMPLATES_DIR" -name "*.tmpl" | sort | while read -r tmpl; do
    echo "  ${tmpl#$TEMPLATES_DIR/}"
  done
  echo

  echo "--- Manifest Entries ---"
  while IFS=: read -r tmpl_rel dest || [[ -n "$tmpl_rel" ]]; do
    [[ -z "$tmpl_rel" || "$tmpl_rel" =~ ^[[:space:]]*# ]] && continue
    dest_expanded="$(expand_dest "$dest")"
    exists="(new)"
    [[ -f "$dest_expanded" ]] && exists="(exists)"
    printf "  %-45s -> %s %s\n" "$tmpl_rel" "$dest" "$exists"
  done < "$MANIFEST"
  echo

  echo "--- Current Settings ---"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] && echo "  $line"
  done < "$SETTINGS_FILE"
  if [[ -f "$MACHINE_SETTINGS" ]]; then
    echo
    echo "  # Machine overrides ($MACHINE_NAME):"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] && echo "  $line"
    done < "$MACHINE_SETTINGS"
  fi
  echo
  exit 0
fi

# ── apply configs ─────────────────────────────────────────────────────────────

echo
echo "=== Applying Config Templates ==="
echo
echo "Machine:  $MACHINE_NAME"
echo "Manifest: $MANIFEST"
echo "Settings: $MACHINE_SETTINGS_STATUS"
$DRY_RUN && echo "Mode:     DRY RUN — no files will be written"
echo

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

N=0
SKIPPED=0

while IFS=: read -r tmpl_rel dest || [[ -n "$tmpl_rel" ]]; do
  # Skip blank lines and comments
  [[ -z "$tmpl_rel" || "$tmpl_rel" =~ ^[[:space:]]*# ]] && continue

  tmpl_rel="${tmpl_rel// /}"   # trim whitespace
  dest="${dest// /}"

  tmpl="$TEMPLATES_DIR/$tmpl_rel"
  dest_expanded="$(expand_dest "$dest")"

  if [[ ! -f "$tmpl" ]]; then
    echo "  WARN: template not found, skipping: $tmpl_rel" >&2
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  echo "  $tmpl_rel"
  echo "  -> $dest_expanded"

  # Render the template
  rendered="$(render "$tmpl")"

  # Special handling for ~/.ssh/config — never silently overwrite
  if [[ "$dest_expanded" == "$HOME/.ssh/config" && -f "$dest_expanded" ]]; then
    SAFE_DEST="$HOME/.ssh/config.mac-security"
    echo "  Note: ~/.ssh/config exists — writing to $SAFE_DEST to avoid overwriting."
    echo "        Review and merge into ~/.ssh/config manually."
    dest_expanded="$SAFE_DEST"
  fi

  # Diff against existing file
  if [[ -f "$dest_expanded" ]]; then
    diff_output="$(diff <(cat "$dest_expanded") <(echo "$rendered") || true)"
    if [[ -z "$diff_output" ]]; then
      echo "  (no changes)"
      echo
      continue
    fi
    echo "  Diff (- existing, + new):"
    echo "$diff_output" | head -30 | sed 's/^/    /'
    [[ "$(echo "$diff_output" | wc -l)" -gt 30 ]] && echo "    ... (truncated)"
  else
    echo "  (new file)"
  fi

  if $DRY_RUN; then
    echo "  [dry-run] Would write: $dest_expanded"
    echo
    N=$((N+1))
    continue
  fi

  # Backup existing file
  if [[ -f "$dest_expanded" ]]; then
    BACKUP="${dest_expanded}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$dest_expanded" "$BACKUP"
    echo "  Backed up: $BACKUP"
  fi

  # Create parent directory if needed
  mkdir -p "$(dirname "$dest_expanded")"

  # Create SSH ControlPath directory if needed
  if [[ "$tmpl_rel" == ssh/* ]]; then
    mkdir -p "$HOME/.ssh/control"
    chmod 700 "$HOME/.ssh/control"
  fi

  # Write rendered file
  printf '%s\n' "$rendered" > "$dest_expanded"
  echo "  Written: $dest_expanded"
  echo
  N=$((N+1))

done < "$MANIFEST"

# ── summary ───────────────────────────────────────────────────────────────────

echo
if $DRY_RUN; then
  echo "Dry run complete. $N template(s) would be applied, $SKIPPED skipped."
  echo "Remove --dry-run to write files."
else
  echo "Done. $N config(s) applied, $SKIPPED skipped."
  [[ $N -gt 0 ]] && echo "Backups saved as <destination>.bak.<timestamp>"
fi
echo
echo "Tips:"
echo "  List templates and settings:  bash scripts/apply-configs.sh --list"
echo "  Preview changes:              bash scripts/apply-configs.sh --dry-run"
echo "  Per-machine settings:         private/machines/${MACHINE_NAME}/configs.env"
echo
