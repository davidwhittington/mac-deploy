# SSH Public Key Authentication on macOS

How to set up key-based SSH access between macOS workstations - and lock down password authentication so keys are the only way in.

**Applies to:** macOS Ventura / Sonoma / Sequoia / Tahoe · OpenSSH (system-bundled)

---

## Overview

Password authentication over SSH is a persistent target for brute-force attacks and credential stuffing. Public key authentication replaces the password with a cryptographic key pair: a **private key** that stays on your client machine and never leaves it, and a **public key** that gets placed on any machine you want to SSH into.

Once keys are in place, you disable password auth entirely - the server will only accept connections from clients holding the matching private key.

---

## Concepts

| Term | What it is |
|------|-----------|
| **Private key** | Secret file on your client (`~/.ssh/id_ed25519`). Never share or copy this off the client. |
| **Public key** | Shareable counterpart (`~/.ssh/id_ed25519.pub`). Placed on servers you want to access. |
| **authorized_keys** | File on the server (`~/.ssh/authorized_keys`) listing public keys that are permitted to connect. |
| **ssh-agent** | Process that holds your decrypted private key in memory so you don't re-enter the passphrase every time. |

---

## Step 1 - Generate a Key Pair (Client)

Do this on the machine you'll be connecting **from**. If you already have a key you want to use, skip to Step 2.

```bash
ssh-keygen -t ed25519 -C "david@macbook-pro"
```

- **`-t ed25519`** - use Ed25519 (modern, compact, faster than RSA)
- **`-C`** - comment to identify the key; use something meaningful like `user@hostname`

When prompted:
- **Key location:** accept the default (`~/.ssh/id_ed25519`) unless you have a reason to change it
- **Passphrase:** set one - this encrypts the private key at rest. macOS Keychain will manage it so you only enter it once per session.

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/Users/david/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase): ••••••••
Your identification has been saved in /Users/david/.ssh/id_ed25519
Your public key has been saved in /Users/david/.ssh/id_ed25519.pub
```

View your public key (this is safe to share):

```bash
cat ~/.ssh/id_ed25519.pub
# ssh-ed25519 AAAA... david@macbook-pro
```

---

## Step 2 - Copy the Public Key to the Server

**Option A - `ssh-copy-id` (easiest, requires password auth to still be on):**

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub david@<target-hostname-or-ip>
```

This appends your public key to `~/.ssh/authorized_keys` on the target machine automatically.

**Option B - Manual copy:**

```bash
# On the target machine, create the .ssh directory if needed
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Paste your public key into authorized_keys
echo "ssh-ed25519 AAAA... david@macbook-pro" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Option C - From local machine via pipe (if you can already SSH in):**

```bash
cat ~/.ssh/id_ed25519.pub | ssh david@<target> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

---

## Step 3 - Enable SSH on the Target Mac

SSH (Remote Login) on macOS is off by default. Enable it in System Settings:

```
System Settings → General → Sharing → Remote Login → On
```

Or via command line (requires admin):

```bash
sudo systemsetup -setremotelogin on
```

Verify it's listening:

```bash
sudo lsof -iTCP:22 -sTCP:LISTEN -P -n
```

---

## Step 4 - Test Key Auth Before Disabling Passwords

**Critical:** verify key auth works *before* disabling password auth. Do this in a separate terminal session - don't close your existing connection until you confirm access.

```bash
# From the client, connect with verbose output to confirm key is used
ssh -v -i ~/.ssh/id_ed25519 david@<target>
```

Look for:

```
debug1: Offering public key: /Users/david/.ssh/id_ed25519 ED25519
debug1: Server accepts key
Authenticated to <target> ([...]:22) using "publickey".
```

If you see `Authenticated using "publickey"` - you're good to proceed.

---

## Step 5 - Harden sshd: Disable Password Auth

macOS uses `/etc/ssh/sshd_config.d/` for drop-in configuration (files here override the base config). Create a hardening file:

```bash
sudo tee /etc/ssh/sshd_config.d/099-hardening.conf << 'EOF'
# Pubkey auth only - no passwords, no root
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries 3
LoginGraceTime 30
EOF
```

Validate the config before reloading:

```bash
sudo sshd -t && echo "Config OK"
```

Reload sshd (no need to restart; sends SIGHUP):

```bash
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
sudo launchctl load /System/Library/LaunchDaemons/ssh.plist
```

Or on newer macOS:

```bash
sudo launchctl kickstart -k system/com.openssh.sshd
```

---

## Step 6 - Verify Password Auth Is Rejected

From the client, attempt a password login (should fail):

```bash
ssh -o PubkeyAuthentication=no -o PasswordAuthentication=yes david@<target>
```

Expected:

```
david@<target>: Permission denied (publickey).
```

---

## Step 7 - Add Key to macOS Keychain (Client)

So you don't re-enter the passphrase every reboot:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to `~/.ssh/config` to use Keychain automatically:

```
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

---

## Deploying to Multiple Machines

When setting up SSH across a fleet of lab machines, the workflow is:

1. Generate one key pair on your **primary client** (or one per client if you prefer separate keys per machine)
2. For each target machine:
   - Enable Remote Login
   - Copy your public key to `~/.ssh/authorized_keys`
   - Drop the hardening config (`099-hardening.conf`)
   - Validate and reload sshd
   - Confirm key auth works
   - Confirm password auth is rejected
3. Document each machine's SSH status in `private/workstations/<hostname>.md`

```bash
# Quickly push your public key to multiple machines while password auth is still on
for host in machine1 machine2 machine3; do
  echo "==> $host"
  ssh-copy-id -i ~/.ssh/id_ed25519.pub david@$host
done
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Permission denied (publickey)` | Key not in authorized_keys | Verify with `cat ~/.ssh/authorized_keys` on server |
| Key accepted but passphrase asked every time | ssh-agent not running | `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` |
| `Bad permissions` error | Wrong file permissions | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| `sshd -t` reports an error | Config syntax issue | Check the specific line reported; validate with `sudo sshd -T` for full config dump |
| Can't connect at all | SSH not enabled | `sudo systemsetup -getremotelogin` - should say "On" |
| Connected but shows wrong user | ssh config override | Check `~/.ssh/config` for conflicting `User` directive |

---

## Security Notes

- **Never copy your private key** (`id_ed25519`, no `.pub`) to another machine - generate a new pair on each client instead
- **Use a passphrase** - a key without one is equivalent to a password written on a sticky note
- **Rotate keys** if a machine is compromised or decommissioned - remove the old public key from all `authorized_keys` files
- **Audit authorized_keys** periodically - run `cat ~/.ssh/authorized_keys` on each server and verify every entry is recognized

---

## Related

- [Security Baseline](../security/README.md) - SSH requirements in the lab security policy
- [Workstation Template](../workstations/TEMPLATE.md) - SSH configuration section in the per-machine doc
- `scripts/audit/security-audit.sh` - audits SSH config and reports findings automatically
