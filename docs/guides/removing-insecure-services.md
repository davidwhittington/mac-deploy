# Removing and Disabling Insecure Services on macOS

macOS ships with a number of sharing and remote access services that can be enabled by accident, re-enabled by system updates, or left on from a previous user's configuration. Each one is an inbound attack surface that has no business running on a machine you're not actively managing remotely.

This guide goes beyond the reference table in `docs/security/README.md` — exact commands, verification steps, and what to do when macOS brings something back after an update.

**Applies to:** macOS Ventura / Sonoma / Sequoia / Tahoe

---

## Before You Start

The audit script will tell you what's running:

```bash
bash scripts/audit/security-audit.sh --brief
```

Check the **Sharing Services** section. Any service marked `⚠️ ENABLED` that you don't actively need should be disabled.

---

## Remote Management (ARD)

**Risk: High.** Apple Remote Desktop gives full screen control, remote command execution, file transfer, and asset reporting over the network. The agent runs continuously and accepts connections even when you're not at the machine. If you're not using ARD to manage this machine from another Mac, there's no reason it should be running.

### Check status

```bash
launchctl list com.apple.RemoteDesktop.agent 2>/dev/null && echo "RUNNING" || echo "Not running"
```

### Disable and deactivate

```bash
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -deactivate \
  -stop \
  -quiet
```

### Verify it's gone

```bash
launchctl list com.apple.RemoteDesktop.agent 2>/dev/null && echo "Still running" || echo "Confirmed stopped"
```

### Confirm it survives reboot

Reboot, then re-run the check. ARD should remain disabled.

### What if it comes back after a macOS update?

System updates occasionally re-enable Remote Management. Add the verification check to your post-update routine, or let the scheduled audit catch it. If you're seeing it re-enable repeatedly, check **System Settings → General → Sharing** — if Remote Management shows as on, macOS may be managing it there rather than via kickstart.

---

## Screen Sharing

**Risk: Medium-High.** Separate from ARD — Screen Sharing is VNC-based remote desktop. Disabled by default but sometimes enabled during troubleshooting and forgotten.

### Check status

```bash
launchctl list com.apple.screensharing 2>/dev/null && echo "RUNNING" || echo "Not running"
```

### Disable

```bash
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
```

Or via System Settings → General → Sharing → Screen Sharing → Off.

### Verify

```bash
launchctl list com.apple.screensharing 2>/dev/null && echo "Still running" || echo "Confirmed stopped"
```

---

## Remote Apple Events

**Risk: Medium.** Allows other Macs on the network to send AppleScript commands to this machine. Rarely needed outside of specific automation workflows. A remote attacker with network access could potentially use this to execute scripts.

### Check status

```bash
launchctl list com.apple.RemoteAppleEvents 2>/dev/null && echo "RUNNING" || echo "Not running"
# Note: also check older daemon name
launchctl list com.apple.remoteevents 2>/dev/null && echo "RUNNING" || true
```

### Disable

System Settings → General → Sharing → Remote Apple Events → Off

Or via command line:

```bash
sudo systemsetup -setremoteappleevents off
```

### Verify

```bash
sudo systemsetup -getremoteappleevents
# Expected: Remote Apple Events: Off
```

---

## Internet Sharing

**Risk: High.** Turns your Mac into a NAT router, sharing its network connection with other devices. Almost certainly not intentional on a lab workstation. If enabled, it opens your machine to traffic from whatever devices connect to it.

### Check status

```bash
launchctl list com.apple.InternetSharing 2>/dev/null && echo "RUNNING" || echo "Not running"
```

### Disable

System Settings → General → Sharing → Internet Sharing → Off

Or:

```bash
sudo launchctl unload /System/Library/LaunchDaemons/com.apple.InternetSharing.plist 2>/dev/null || true
```

### Verify

```bash
launchctl list com.apple.InternetSharing 2>/dev/null && echo "Still running" || echo "Confirmed stopped"
```

---

## Bluetooth Sharing

**Risk: Low-Medium.** Allows remote devices to browse files or push files to your machine over Bluetooth. Low risk but no reason to have it on a machine that isn't explicitly being used as a Bluetooth file transfer endpoint.

### Check status

```bash
launchctl list com.apple.bluetooth.BTServer 2>/dev/null | grep -i sharing || echo "Sharing not explicitly running"
```

Bluetooth Sharing is primarily controlled through System Settings rather than a launchd service.

### Disable

System Settings → General → Sharing → Bluetooth Sharing → Off

---

## File Sharing (SMB and AFP)

**Risk: Medium.** SMB (`smbd`) exposes your filesystem to other machines on the network. AFP (`AppleFileServer`) is the older Apple protocol, largely deprecated. Both are off by default but worth verifying.

### Check status

```bash
launchctl list com.apple.smbd 2>/dev/null && echo "SMB running" || echo "SMB not running"
launchctl list com.apple.AppleFileServer 2>/dev/null && echo "AFP running" || echo "AFP not running"
```

### Disable SMB

```bash
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist
```

### Disable AFP

```bash
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.AppleFileServer.plist
```

Or via System Settings → General → Sharing → File Sharing → Off (disables both).

---

## Wake for Network Access

**Risk: Low-Medium.** Allows the machine to wake from sleep when it receives a network request. Useful for intentional remote access — but if you're not relying on it to wake machines remotely, it's an unnecessary exposure that keeps the network stack partially active during sleep.

### Check status

```bash
sudo systemsetup -getwakeonnetworkaccess
```

### Disable

```bash
sudo systemsetup -setwakeonnetworkaccess off
```

### Verify

```bash
sudo systemsetup -getwakeonnetworkaccess
# Expected: Wake On Network Access: Off
```

---

## AirDrop

**Risk: Low-Medium** in trusted environments, **Higher** on public or shared networks. AirDrop uses Bluetooth and WiFi to discover nearby devices and accept file transfers. "Everyone" mode is the most exposed setting.

### Check and set to Contacts Only or Off

AirDrop has no launchctl service to stop — it's controlled through the Finder or via defaults:

```bash
# Set AirDrop to off (NoDiscovery)
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true

# Or set to Contacts Only (value 1) — requires re-login to take effect
defaults write com.apple.sharingd DiscoverableMode -string "Contacts Only"
```

For lab/server machines with no need for file transfer:

```bash
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
```

---

## Post-Cleanup Verification

After disabling services, run a full audit to confirm the findings are resolved:

```bash
bash scripts/audit/security-audit.sh --save
```

Check the **Sharing Services** and **Findings Summary** sections. All disabled services should show `✅ Disabled` and the related High/Medium findings should no longer appear.

Also check open ports — services that were listening should no longer appear:

```bash
lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
```

---

## What to Do When Services Come Back

macOS updates can re-enable services, particularly Remote Management and Screen Sharing. Two approaches:

**Reactive:** The scheduled audit (`scripts/audit/scheduled-audit.sh`) will catch any service that re-enables itself and log it as drift. Check the drift log after every major update.

**Proactive:** After any macOS update, run:

```bash
bash scripts/audit/security-audit.sh --brief 2>/dev/null | grep -A20 "Sharing Services"
```

Takes ten seconds and immediately shows whether anything came back.

---

## Full Disable Checklist

Run through this on each new or freshly updated machine:

```bash
HOSTNAME=$(hostname -s)
echo "==> Checking services on $HOSTNAME"
echo

for svc in \
  "com.apple.RemoteDesktop.agent:Remote Management (ARD)" \
  "com.apple.screensharing:Screen Sharing" \
  "com.apple.RemoteAppleEvents:Remote Apple Events" \
  "com.apple.remoteevents:Remote Apple Events (alt)" \
  "com.apple.InternetSharing:Internet Sharing" \
  "com.apple.smbd:File Sharing (SMB)" \
  "com.apple.AppleFileServer:File Sharing (AFP)"; do
  svc_id="${svc%%:*}"
  svc_name="${svc##*:}"
  if launchctl list "$svc_id" &>/dev/null; then
    printf "  ⚠️  ENABLED  %s\n" "$svc_name"
  else
    printf "  ✅ Disabled  %s\n" "$svc_name"
  fi
done
```

---

## Related

- [Security Baseline](../security/README.md) — required service states for lab machines
- [Automated Security Drift Detection](automated-security-drift-detection.md) — catch services that re-enable after updates
- `scripts/audit/security-audit.sh` — full audit including sharing services section
