# Firewall on macOS: Application Firewall vs pf

macOS ships with two distinct firewall systems that operate at different layers. Most people only know about one. Understanding both — and when each falls short — is essential for any machine where you need real inbound traffic control.

**Applies to:** macOS Ventura / Sonoma / Sequoia / Tahoe · Apple Silicon and Intel

---

## The Two Firewalls

| | Application Firewall | pf (Packet Filter) |
|---|---|---|
| **Layer** | Application layer | Network layer (kernel) |
| **Granularity** | Per signed application | Per port, protocol, IP |
| **Config location** | System Settings / socketfilterfw | /etc/pf.conf + anchors |
| **Survives reboot** | Yes | Only with a LaunchDaemon |
| **Block-all mode** | Truly blocks everything | Selective by rule |
| **SSH compatible** | No (block-all kills SSH) | Yes (allow port 22 explicitly) |

---

## Application Firewall

The Application Firewall is what you manage in **System Settings → Network → Firewall**. It works at the application level — it decides which signed apps are allowed to accept incoming connections.

### What it does well

- Easy to manage
- No syntax to learn
- Per-app allow/deny that persists across reboots automatically
- Stealth mode (ignore ICMP probes, don't respond to closed ports)

### The block-all problem

"Block all incoming connections" sounds like what you want on an untrusted network. The problem: it is truly all-or-nothing. It overrides every per-app exception, including SSH. Even if you've explicitly allowed `sshd`, block-all wins.

**If you want SSH and block-all at the same time, you need pf.**

### Useful commands

```bash
# Check current state
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Enable the firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode (recommended — ignores pings, doesn't respond to closed ports)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Block all incoming (use only if SSH is not needed)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on

# Allow a specific app
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/sbin/sshd
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/sbin/sshd

# List all rules
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps
```

---

## pf (Packet Filter)

pf is a BSD-originated kernel-level firewall. It's been on macOS since 10.7. macOS uses it internally and loads a base ruleset at boot — you just don't see it by default because no custom rules are configured.

pf gives you port-level control: allow SSH on 22, block everything else inbound. That's the configuration the Application Firewall's block-all mode can't achieve.

### How pf works on macOS

pf uses **anchors** — named rule sets that can be loaded and managed independently without touching the system's base `pf.conf`. The right approach is to add a custom anchor rather than editing `/etc/pf.conf` directly.

The system base config is at `/etc/pf.conf`. Anchors live in `/etc/pf.anchors/`.

### Setting up a custom anchor

**1. Create the anchor file:**

```bash
printf '%s\n' \
  '# mac-deploy pf anchor' \
  '# Inbound rules — block all, then allow specific ports' \
  '' \
  '# Allow established connections (return traffic)' \
  'pass in quick on en0 proto tcp from any to any flags S/SA keep state' \
  '' \
  '# Allow SSH inbound' \
  'pass in quick on en0 proto tcp to port 22' \
  '' \
  '# Block all other inbound' \
  'block in on en0' \
  '' \
  '# Allow all outbound' \
  'pass out all keep state' \
  | sudo tee /etc/pf.anchors/mac-deploy
```

> Replace `en0` with your active interface. Check with: `networksetup -listallhardwareports | grep -A1 "Wi-Fi\|Ethernet"`

**2. Reference the anchor in /etc/pf.conf:**

```bash
# Check current pf.conf
cat /etc/pf.conf
```

Add these lines (edit with sudo):

```
anchor "mac-deploy"
load anchor "mac-deploy" from "/etc/pf.anchors/mac-deploy"
```

**3. Load and test:**

```bash
# Load the rules
sudo pfctl -f /etc/pf.conf

# Enable pf
sudo pfctl -e

# Check it's running
sudo pfctl -s info

# See loaded rules
sudo pfctl -s rules

# Test — from another machine, try connecting to a blocked port
# nmap -p 80 <this-machine-ip>   # should be filtered
# ssh <this-machine-ip>           # should work
```

### Making pf persist across reboots

pf rules don't survive a reboot without a LaunchDaemon. The plist is stored in the repo at `config/launchdaemons/com.mac-deploy.pf.plist`. Deploy it with:

```bash
sudo cp config/launchdaemons/com.mac-deploy.pf.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.mac-deploy.pf.plist
```

Verify after next reboot:

```bash
sudo pfctl -s rules
```

---

## Recommended Configuration for Lab Machines

For a machine that needs SSH accessible but otherwise hardened:

| Setting | Value | How |
|---------|-------|-----|
| Application Firewall | Enabled | System Settings or socketfilterfw |
| Stealth mode | Enabled | `--setstealthmode on` |
| Block-all | **Off** | Use pf instead |
| pf | Enabled with anchor | `/etc/pf.anchors/mac-deploy` |
| SSH via pf | Allowed on port 22 | Anchor rule |
| All other inbound | Blocked via pf | Anchor default block |

This gives you port-level control (better than block-all) while keeping SSH accessible — and stealth mode on the Application Firewall means the machine won't respond to pings or port probes on closed ports.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| pf rules lost after reboot | No LaunchDaemon | Create the plist above |
| SSH blocked despite allow rule | Interface name wrong | Check `ifconfig` for active interface |
| `pfctl: /etc/pf.conf: ...` error | Syntax error in rules | Run `sudo pfctl -n -f /etc/pf.conf` to dry-run |
| Rules load but nothing is blocked | pf not enabled | `sudo pfctl -e` |
| Can't reach machine at all | Overly broad block rule | Connect locally, check `sudo pfctl -s rules` |
| Application Firewall block-all still on | Conflict with pf intent | Disable it: `--setblockall off` |

---

## Related

- [SSH Pubkey Authentication](ssh-pubkey-auth.md) — set up key-based SSH before hardening the firewall
- [Security Baseline](../security/README.md) — firewall requirements in the lab policy
- `scripts/audit/security-audit.sh` — audits Application Firewall state; pf check coming in a future update
