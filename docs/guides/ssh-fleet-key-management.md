# SSH Key Management Across a Lab Fleet

Single-machine SSH is straightforward. Managing keys cleanly across a fleet of lab workstations requires conventions — otherwise you end up with orphaned authorized_keys entries, mystery keys with no names, and no idea which client can reach which server.

**Applies to:** macOS lab environments · OpenSSH · multiple machines

> **Prerequisite:** [SSH Pubkey Authentication](ssh-pubkey-auth.md) — covers single-machine key setup. This guide picks up from there.

---

## Key Strategy: Per-Client vs Shared Keys

The first decision is whether each client machine gets its own key pair or whether you use one key pair across all clients.

| Strategy | Pros | Cons |
|----------|------|------|
| **Per-client keys** | Revoke one machine without affecting others; clear audit trail | More authorized_keys entries to manage |
| **Shared key** | One key to manage, one authorized_keys entry per server | Compromise of any client means rotating everywhere |

**Recommendation for a personal lab:** per-client keys. Each of your machines gets its own ed25519 key. When a machine is retired, you remove exactly one entry from authorized_keys on every server. Clean, traceable, no blast radius from a single compromise.

---

## Naming Convention

Good key naming makes fleet management possible. Use: `user@hostname-purpose`

```bash
# On each client machine, generate with a meaningful comment
ssh-keygen -t ed25519 -C "david@macbook-pro-lab"
ssh-keygen -t ed25519 -C "david@mac-mini-build"
ssh-keygen -t ed25519 -C "david@mac-studio-main"
```

The comment ends up in authorized_keys on every server — it's the only way to identify which key belongs to which machine when auditing.

---

## ~/.ssh/config — Host Blocks for Each Lab Machine

A well-maintained `~/.ssh/config` eliminates typing full usernames, IPs, and flags for every connection. One entry per lab machine:

```
# Global defaults
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 60
  ServerAliveCountMax 3

# Lab machines
Host mac-mini
  HostName mac-mini.local
  User david
  IdentityFile ~/.ssh/id_ed25519

Host mac-studio
  HostName mac-studio.local
  User david
  IdentityFile ~/.ssh/id_ed25519

Host build-server
  HostName 192.168.1.50
  User david
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

With this in place:

```bash
ssh mac-mini       # instead of: ssh david@mac-mini.local
ssh mac-studio     # instead of: ssh david@192.168.1.x
```

Use `.local` mDNS names for machines on your local network — they resolve without a DNS server as long as Bonjour is running.

---

## Fleet Deployment: Pushing Keys to All Machines

### Initial deployment (while password auth is still on)

```bash
# Push your public key to every lab machine
for host in mac-mini mac-studio build-server; do
  echo "==> $host"
  ssh-copy-id -i ~/.ssh/id_ed25519.pub david@$host && echo "    OK" || echo "    FAILED"
done
```

### After password auth is disabled

Once `PasswordAuthentication no` is set, you can no longer use `ssh-copy-id`. To add a new key to a machine you already have access to:

```bash
# From a client that already has key access
cat ~/.ssh/id_ed25519.pub | ssh mac-mini "cat >> ~/.ssh/authorized_keys"
```

Or copy it manually if you have physical/console access.

---

## Key Rotation

When a machine is compromised, decommissioned, or transferred, rotate its key:

**1. Generate a new key on the replacement or recovered client:**

```bash
ssh-keygen -t ed25519 -C "david@macbook-pro-lab" -f ~/.ssh/id_ed25519_new
```

**2. Push the new public key to all servers (using existing access):**

```bash
for host in mac-mini mac-studio build-server; do
  echo "==> $host"
  cat ~/.ssh/id_ed25519_new.pub | ssh $host "cat >> ~/.ssh/authorized_keys"
done
```

**3. Verify new key works before removing the old one:**

```bash
ssh -i ~/.ssh/id_ed25519_new mac-mini "echo OK"
```

**4. Remove the old key from all servers:**

```bash
OLD_KEY=$(cat ~/.ssh/id_ed25519.pub)

for host in mac-mini mac-studio build-server; do
  echo "==> $host"
  ssh $host "grep -v '$OLD_KEY' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys"
done
```

**5. Replace the local key files:**

```bash
mv ~/.ssh/id_ed25519_new ~/.ssh/id_ed25519
mv ~/.ssh/id_ed25519_new.pub ~/.ssh/id_ed25519.pub
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

---

## Auditing authorized_keys Across the Fleet

Run periodically to verify only known, expected keys are authorized on every server.

```bash
#!/usr/bin/env bash
# audit-authorized-keys.sh
# Run from any client with SSH access to all lab machines

SERVERS="mac-mini mac-studio build-server"

for host in $SERVERS; do
  echo "=== $host ==="
  ssh "$host" "cat ~/.ssh/authorized_keys" 2>/dev/null | while IFS= read -r line; do
    # Extract the comment (3rd field)
    comment=$(echo "$line" | awk '{print $3}')
    keytype=$(echo "$line" | awk '{print $1}')
    echo "  [$keytype] $comment"
  done
  echo
done
```

Expected output — every line should be a key you recognize:

```
=== mac-mini ===
  [ssh-ed25519] david@macbook-pro-lab
  [ssh-ed25519] david@mac-studio-main

=== mac-studio ===
  [ssh-ed25519] david@macbook-pro-lab
```

If you see `[ssh-rsa]`, `(null)`, or an unrecognized comment, investigate before assuming it's benign.

---

## Documenting Fleet SSH Status

After setting up each machine, record its SSH state in the private submodule:

`private/workstations/<hostname>.md` — SSH section:

```markdown
## SSH

| Setting | Value |
|---------|-------|
| Remote Login | Enabled |
| Port | 22 |
| PasswordAuthentication | no |
| PermitRootLogin | no |
| Authorized clients | david@macbook-pro-lab, david@mac-studio-main |
| Last key rotation | 2026-03-08 |
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Permission denied (publickey)` after rotation | Old key removed before new one verified | Add new key back; verify before removing old |
| authorized_keys has duplicate entries | ssh-copy-id run twice | `sort -u ~/.ssh/authorized_keys > tmp && mv tmp ~/.ssh/authorized_keys` on server |
| Unknown key comment in authorized_keys | Key added without `-C` flag or copied from elsewhere | Identify by fingerprint: `ssh-keygen -l -f key.pub`; remove if unknown |
| mDNS name not resolving (`.local`) | Target machine sleeping or Bonjour off | Wake machine or use IP; check `dns-sd -B _ssh._tcp` |
| ssh-agent not forwarding on remote | AgentForwarding not configured | Add `ForwardAgent yes` to the Host block in ~/.ssh/config |

---

## Related

- [SSH Pubkey Authentication](ssh-pubkey-auth.md) — single-machine key setup and sshd hardening
- [Firewall: Application Firewall vs pf](firewall-pf-vs-application-firewall.md) — allowing SSH through the firewall
- `scripts/audit/security-audit.sh` — audits SSH server config on each machine
- `private/workstations/` — per-machine SSH status documentation
