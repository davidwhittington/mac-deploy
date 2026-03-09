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

The wrapper script is already in the repo at `scripts/audit/scheduled-audit.sh`. If you're setting up a new machine, clone the repo and make it executable:

```bash
chmod +x scripts/audit/scheduled-audit.sh
```

The script runs the audit, saves the report to `private/workstations/`, diffs it against the previous report, and writes a drift summary to the drift log if anything changed. It also calls `logger` so drift alerts appear in Console.app.

---

## Part 2 — LaunchAgent Plist

LaunchAgents run as your user. LaunchDaemons run as root. For reading security state (FileVault, Gatekeeper, firewall), a LaunchAgent is sufficient — the audit script is designed to work without sudo.

The plist is stored in the repo at `config/launchagents/com.mac-deploy.security-audit.plist`. Deploy it with:

```bash
mkdir -p ~/Library/LaunchAgents
cp config/launchagents/com.mac-deploy.security-audit.plist ~/Library/LaunchAgents/
```

> The plist references `REPO_PATH/scripts/audit/scheduled-audit.sh`. Edit that string to match your actual repo location before loading.

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
