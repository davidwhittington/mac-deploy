# New Machine Setup Checklist

A step-by-step checklist for bringing a macOS workstation from factory state to a hardened, documented baseline. Covers everything from initial update through security hardening, SSH configuration, and audit history.

**Applies to:** macOS Ventura / Sonoma / Sequoia / Tahoe · Apple Silicon and Intel

---

## Before You Start

Have the following ready:

- Apple ID and iCloud credentials (for Activation Lock, iCloud Keychain)
- Your SSH public key, if you plan to access this machine remotely
- Access to your password manager (recovery keys, credentials)
- Network access

Estimated time: 20-40 minutes depending on Homebrew installs and macOS update size.

---

## Step 1 — macOS Updates

Get to the latest release before doing anything else. Security patches apply to the OS, not just apps.

```bash
# Check current version
sw_vers

# Open Software Update
open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
```

Install all available updates. Reboot if prompted. Repeat until no updates remain.

Verify automatic update settings are on:

```
System Settings → General → Software Update → Automatic Updates → all enabled
```

---

## Step 2 — FileVault

Enable disk encryption before creating user accounts or installing software. If the machine ships with it off, turn it on now.

```
System Settings → Privacy & Security → FileVault → Turn On
```

**Save the recovery key somewhere safe** — your password manager is the right place. Without it, a forgotten login password means permanent data loss.

See [FileVault Recovery Key Management](filevault-recovery-keys.md) for the full key management workflow.

Verify it's encrypting:

```bash
fdesetup status
# FileVault is On.
```

---

## Step 3 — Install Homebrew

Homebrew is the package manager for everything that follows.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple Silicon, add brew to your PATH:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify:

```bash
brew --version
```

---

## Step 4 — Install mac-security

```bash
brew tap davidwhittington/mac-security
brew install davidwhittington/mac-security/mac-security
```

This installs all mac-security tools on your PATH:

| Command | Purpose |
|---------|---------|
| `mac-security-audit` | Security posture audit |
| `mac-security-harden-ssh` | SSH hardening |
| `mac-security-firewall` | Application Firewall hardening |
| `mac-security-defaults` | macOS system preference hardening |
| `mac-security-configs` | Config template rendering |
| `mac-security-capture` | Machine profile snapshot |

Or clone the full repo for the audit history and private submodule workflow:

```bash
git clone https://github.com/davidwhittington/mac-security.git
cd mac-security
git submodule update --init --recursive
```

---

## Step 5 — Baseline Audit

Run the audit before making changes to capture the starting state.

```bash
mac-security-audit --brief
```

Review the Findings Summary at the bottom. Common findings on a new machine:

- FileVault disabled (if skipped in Step 2)
- Application Firewall off
- SSH password auth not explicitly disabled
- Bluetooth on
- World-readable files in `~/.ssh` or `~/.aws`

Save the baseline report:

```bash
mac-security-audit --save
```

---

## Step 6 — SSH Key Setup

If you plan to SSH into this machine or use it to SSH into others, set up keys now before disabling password auth.

**Generate a key on this machine (if it doesn't have one):**

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"
```

**Add to macOS Keychain so the passphrase is remembered:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

**Add to `~/.ssh/config`:**

```
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

**If other machines need to SSH into this one**, copy your client public key to `~/.ssh/authorized_keys` before the next step disables password auth.

See [SSH Public Key Authentication](ssh-pubkey-auth.md) for the full walkthrough.

---

## Step 7 — SSH Hardening

Disables password authentication and locks down the SSH server config.

```bash
sudo mac-security-harden-ssh
```

Or from the repo:

```bash
sudo bash scripts/harden-sshd.sh
```

Preview first with `--dry-run`. After applying, confirm you can still connect via key before closing your terminal session.

---

## Step 8 — Firewall

Enable the Application Firewall with stealth mode. If this machine needs SSH accessible from the network, add pf for port-level control.

```bash
# Application Firewall + stealth mode only
sudo mac-security-firewall

# With pf (allow SSH inbound, block everything else)
sudo mac-security-firewall --with-pf
```

See [Firewall: Application Firewall vs pf](firewall-pf-vs-application-firewall.md) for the tradeoffs.

---

## Step 9 — System Defaults

Apply hardened macOS system preferences: screen lock, screenshot location, Finder settings, Mail remote content blocking, Safari security, AirDrop restrictions.

```bash
# Preview changes first
mac-security-defaults --dry-run

# Apply (software update settings require sudo)
mac-security-defaults
sudo mac-security-defaults
```

---

## Step 10 — Disable Unnecessary Sharing Services

On a workstation that doesn't need to share files or accept remote management, disable all sharing services.

```
System Settings → General → Sharing
```

Turn off everything not actively needed:

- Remote Management (ARD)
- Screen Sharing
- File Sharing
- Remote Login (if SSH is not needed)
- Remote Apple Events
- Internet Sharing
- Bluetooth Sharing

See [Removing Insecure Services](removing-insecure-services.md) for per-service verification commands and launchctl checks.

---

## Step 11 — Config Templates (Optional)

If you're standardizing configs across multiple machines, apply the config templates:

```bash
# From the cloned repo — review settings first
mac-security-configs --list
mac-security-configs --dry-run
mac-security-configs
```

Per-machine settings live in `private/machines/<hostname>/configs.env`. Add your name, email, SSH key path, and any other variables before running.

---

## Step 12 — Capture Machine Profile

Snapshot the machine's current state into the private submodule.

```bash
# From the cloned repo
bash pkgs/capture.sh
```

This saves the Brewfile, shell config, git config, and macOS defaults to `private/machines/<hostname>/`.

---

## Step 13 — Final Audit

Re-run the audit to confirm all findings are resolved.

```bash
mac-security-audit --brief
```

The Findings Summary should show **No critical findings** or only expected items (Bluetooth on, developer mode on dev machines).

Save the post-hardening report:

```bash
mac-security-audit --save
```

Commit the reports to the private submodule:

```bash
cd private
git add workstations/ machines/
git commit -m "audit: <hostname> initial baseline $(date +%Y-%m-%d)"
git push
```

---

## Step 14 — Schedule Drift Detection

Set up the daily audit scheduler so you get alerted if anything changes.

```bash
# From the repo root
cp config/launchagents/com.mac-security.security-audit.plist ~/Library/LaunchAgents/
# Edit the plist to confirm the path matches your repo location
launchctl load ~/Library/LaunchAgents/com.mac-security.security-audit.plist
```

See [Automated Security Drift Detection](automated-security-drift-detection.md) for the full setup.

---

## Step 15 — Document the Machine

Add the machine to the workstation inventory and create a machine doc.

```
docs/workstations/README.md   — add a row to the inventory table
docs/workstations/<hostname>.md — create from TEMPLATE.md
```

---

## Checklist Summary

```
[ ] macOS fully updated
[ ] FileVault enabled, recovery key saved
[ ] Homebrew installed
[ ] mac-security installed
[ ] Baseline audit run and saved
[ ] SSH key generated and added to Keychain
[ ] authorized_keys populated (if remote access needed)
[ ] SSH hardened (harden-sshd.sh)
[ ] Application Firewall enabled with stealth mode
[ ] System defaults applied
[ ] Unnecessary sharing services disabled
[ ] Config templates applied (if using)
[ ] Machine profile captured
[ ] Final audit: no critical findings
[ ] Drift detection scheduled
[ ] Machine documented in inventory
```

---

## Related

- [SSH Public Key Authentication](ssh-pubkey-auth.md)
- [Firewall: Application Firewall vs pf](firewall-pf-vs-application-firewall.md)
- [FileVault Recovery Key Management](filevault-recovery-keys.md)
- [Removing Insecure Services](removing-insecure-services.md)
- [Automated Security Drift Detection](automated-security-drift-detection.md)
- `scripts/audit/security-audit.sh` — the audit script
