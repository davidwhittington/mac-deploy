# Automated Security Drift Detection with launchd

Running the security audit manually tells you the state of a machine right now. Scheduling it tells you when something changes. This guide turns the audit script into an active monitoring layer — running on a schedule, diffing against the last known-good report, and flagging drift automatically.

**Applies to:** macOS Ventura / Sonoma / Sequoia / Tahoe · requires mac-deploy repo cloned on each machine

---

## What Drift Looks Like

Security state doesn't only change when you make a change. macOS updates can re-enable services. An app install can open a new listening port. A misconfigured script can disable Gatekeeper. Remote Management turns itself back on.

A scheduled audit catches these things. Without it, you find out at the next manual audit — or not at all.

---

## Overview

The setup has two parts:

1. **A wrapper script** (`scripts/audit/scheduled-audit.sh`) that runs the audit, diffs against the previous report, and writes a drift summary if anything changed
2. **A LaunchAgent plist** that runs the wrapper on a schedule

Reports land in `private/workstations/` (the private submodule) so the history accumulates and can be committed.

---

## Part 1 — The Scheduled Audit Wrapper

```bash
sudo tee /Users/david/Documents/projects/mac-deploy/scripts/audit/scheduled-audit.sh << 'SCRIPT'
#!/usr/bin/env bash
# scheduled-audit.sh — run security audit, diff against last report, log drift
# Designed to be called by launchd. Output goes to system log.

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

PREV_REPORT=$(ls "$PRIVATE_DIR/${HOSTNAME}"-*.md 2>/dev/null | grep -v "$DATE" | sort | tail -1)

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
echo "[$(date)] Compared: $(basename "$PREV_REPORT") → $(basename "$REPORT")" | tee -a "$DRIFT_LOG"
echo "" | tee -a "$DRIFT_LOG"

diff <(echo "$PREVIOUS") <(echo "$CURRENT") | tee -a "$DRIFT_LOG" || true

echo "" | tee -a "$DRIFT_LOG"
echo "[$(date)] Full diff: diff '$PREV_REPORT' '$REPORT'" | tee -a "$DRIFT_LOG"

# Write to macOS system log so it appears in Console.app
/usr/bin/logger -t "mac-deploy-audit" "SECURITY DRIFT on $HOSTNAME — check $DRIFT_LOG"
SCRIPT
```

Make it executable:

```bash
chmod +x /Users/david/Documents/projects/mac-deploy/scripts/audit/scheduled-audit.sh
```

---

## Part 2 — LaunchAgent Plist

LaunchAgents run as your user. LaunchDaemons run as root. For reading security state (FileVault, Gatekeeper, firewall), a LaunchAgent is sufficient — the audit script is designed to work without sudo.

```bash
mkdir -p ~/Library/LaunchAgents

cat > ~/Library/LaunchAgents/com.mac-deploy.security-audit.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.mac-deploy.security-audit</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/david/Documents/projects/mac-deploy/scripts/audit/scheduled-audit.sh</string>
  </array>

  <!-- Run daily at 8:00 AM -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/tmp/mac-deploy-audit.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/mac-deploy-audit-error.log</string>

  <!-- Run on next opportunity if the scheduled time was missed (e.g. machine was asleep) -->
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.mac-deploy.security-audit.plist

# Verify it's loaded
launchctl list | grep mac-deploy
```

---

## Running It Manually to Test

```bash
# Trigger a run now without waiting for the schedule
launchctl start com.mac-deploy.security-audit

# Watch the drift log
tail -f ~/Documents/projects/mac-deploy/private/workstations/$(hostname -s)-drift.log
```

---

## Adjusting the Schedule

Change the `StartCalendarInterval` in the plist to suit your preference:

```xml
<!-- Every day at 8 AM (default above) -->
<key>Hour</key><integer>8</integer>
<key>Minute</key><integer>0</integer>

<!-- Every Monday at 7 AM -->
<key>Weekday</key><integer>1</integer>
<key>Hour</key><integer>7</integer>
<key>Minute</key><integer>0</integer>

<!-- First of every month -->
<key>Day</key><integer>1</integer>
<key>Hour</key><integer>6</integer>
<key>Minute</key><integer>0</integer>
```

After editing the plist, reload it:

```bash
launchctl unload ~/Library/LaunchAgents/com.mac-deploy.security-audit.plist
launchctl load ~/Library/LaunchAgents/com.mac-deploy.security-audit.plist
```

---

## Committing Audit History

Reports accumulate in `private/workstations/`. Commit them periodically to build a dated audit trail:

```bash
cd ~/Documents/projects/mac-deploy/private
git add workstations/
git commit -m "audit: $(hostname -s) scheduled reports $(date +%Y-%m)"
git push
```

Or automate it by appending to `scheduled-audit.sh`:

```bash
# At the end of scheduled-audit.sh, after the drift check
cd "$REPO_ROOT/private"
git add workstations/ 2>/dev/null || true
git diff --cached --quiet || git commit -m "audit: $HOSTNAME $DATE (scheduled)"
```

---

## What Triggers a Drift Alert

The wrapper compares lines matching security-relevant keywords between the current and previous report. Things that will trigger an alert:

| Change | Detected |
|--------|---------|
| FileVault disabled | Yes |
| SIP disabled | Yes |
| Gatekeeper disabled | Yes |
| Application Firewall disabled | Yes |
| Stealth mode turned off | Yes |
| New sharing service enabled | Yes — `ENABLED` keyword |
| Findings Summary changes | Yes — new or resolved findings |
| New open port | Partially — only if labeled ENABLED/DISABLED |

For full port-level drift detection, extend `extract_posture()` to also capture the listening ports section.

---

## Viewing Alerts in Console.app

The script writes to the system log via `logger`. To see drift alerts:

1. Open **Console.app**
2. Search for `mac-deploy-audit` in the search bar
3. Filter by **Any** to see all severity levels

Or from the terminal:

```bash
log show --predicate 'senderImagePath contains "logger"' --info --last 7d | grep mac-deploy
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Agent not running after reboot | Plist not loaded | `launchctl load ~/Library/LaunchAgents/com.mac-deploy.security-audit.plist` |
| No output / empty log | Script path wrong in plist | Verify path matches repo location |
| `private/workstations/` not found | Submodule not initialized | `git submodule update --init` in repo root |
| Drift detected on every run | `extract_posture` matching something that changes daily | Adjust the grep pattern to exclude dynamic content |
| Missed runs when asleep | Expected — launchd won't wake machine | Set `RunAtLoad true` to run on next login instead |

---

## Related

- `scripts/audit/security-audit.sh` — the underlying audit script
- [SSH Pubkey Authentication](ssh-pubkey-auth.md)
- [Firewall: Application Firewall vs pf](firewall-pf-vs-application-firewall.md)
- `private/workstations/` — audit report history (private submodule)
