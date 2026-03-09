#!/usr/bin/env bash
# scheduled-audit.sh — run security audit, diff against last report, log drift
# Designed to be called by launchd. Output goes to system log.
#
# Usage: bash scripts/audit/scheduled-audit.sh
# Setup:  see docs/guides/automated-security-drift-detection.md

set -euo pipefail

HOSTNAME=$(hostname -s)
DATE=$(date +%Y-%m-%d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PRIVATE_DIR="$REPO_ROOT/private/workstations"
REPORT="$PRIVATE_DIR/${HOSTNAME}-${DATE}.md"
DRIFT_LOG="$PRIVATE_DIR/${HOSTNAME}-drift.log"

mkdir -p "$PRIVATE_DIR"

# ── Run the audit ─────────────────────────────────────────────────────────────

echo "[$(date)] Starting scheduled security audit for $HOSTNAME" | tee -a "$DRIFT_LOG"
bash "$SCRIPT_DIR/security-audit.sh" > "$REPORT" 2>/dev/null
echo "[$(date)] Audit complete: $REPORT" | tee -a "$DRIFT_LOG"

# ── Find the previous report to diff against ──────────────────────────────────

PREV_REPORT=$(ls "$PRIVATE_DIR/${HOSTNAME}"-*.md 2>/dev/null | grep -v "$DATE" | sort | tail -1 || true)

if [[ -z "$PREV_REPORT" ]]; then
  echo "[$(date)] No previous report found — establishing baseline" | tee -a "$DRIFT_LOG"
  exit 0
fi

# ── Extract key security fields for comparison ────────────────────────────────

extract_posture() {
  local file="$1"
  grep -E \
    "FileVault is|SIP is|Gatekeeper|Firewall is|stealth mode|block all|ENABLED|DISABLED|Findings Summary" \
    "$file" 2>/dev/null || true
}

CURRENT=$(extract_posture "$REPORT")
PREVIOUS=$(extract_posture "$PREV_REPORT")

if [[ "$CURRENT" == "$PREVIOUS" ]]; then
  echo "[$(date)] No security drift detected" | tee -a "$DRIFT_LOG"
  exit 0
fi

# ── Drift detected ────────────────────────────────────────────────────────────

echo "[$(date)] *** SECURITY DRIFT DETECTED ***" | tee -a "$DRIFT_LOG"
echo "[$(date)] Compared: $(basename "$PREV_REPORT") -> $(basename "$REPORT")" | tee -a "$DRIFT_LOG"
echo "" | tee -a "$DRIFT_LOG"

diff <(echo "$PREVIOUS") <(echo "$CURRENT") | tee -a "$DRIFT_LOG" || true

echo "" | tee -a "$DRIFT_LOG"
echo "[$(date)] Full diff: diff '$PREV_REPORT' '$REPORT'" | tee -a "$DRIFT_LOG"

# Write to macOS system log so it appears in Console.app
/usr/bin/logger -t "mac-security-audit" "SECURITY DRIFT on $HOSTNAME — check $DRIFT_LOG"
