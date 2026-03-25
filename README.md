# mac-security

A personal toolkit for deploying, standardizing, and auditing macOS workstations across lab environments. Scripts to capture and restore full machine environments, security posture auditing with markdown output, and shell configuration symmetry across machines.

Designed to be **repeatable and auditable** - run the audit script on any machine and get a consistent, structured report. Capture a working environment and restore it identically elsewhere.

**Tested on:** macOS Sequoia / Tahoe · Apple Silicon (M-series) · zsh

**Website:** [davidwhittington.github.io/mac-security](https://davidwhittington.github.io/mac-security)

---

## Background

Managing multiple workstations across lab environments creates drift - different packages installed, different shell configs, inconsistent security settings, no record of what's running where. This toolkit came out of the need to answer basic questions reliably: *Is FileVault on? What's listening on the network? When was this machine last audited? How do I get a new machine to look like the others?*

The goal is a standardized baseline: repeatable deployment, consistent shell environment, and a documented security posture for every machine - with actual per-machine data kept private and out of the public repo.

---

## What It Covers

| Area | Coverage |
|------|---------|
| **Security Audit** | FileVault, SIP, Gatekeeper, firewall, SSH config, open ports, sharing services, user accounts, update policy |
| **Package Capture** | Homebrew formulae + casks via Brewfile, tap list |
| **Shell Config** | zsh, Oh My Zsh / Prezto / Starship, aliases, environment |
| **Deployment** | Restore a full machine profile from a saved snapshot |
| **Documentation** | Per-machine markdown docs, security baseline, guides |

---

## Repository Structure

```
mac-security/
├── docs/
│   ├── guides/           # Technical how-to articles
│   ├── security/         # Security baseline and policy
│   └── workstations/     # Per-machine doc template and inventory
├── pkgs/
│   ├── capture.sh        # Snapshot current machine → private/machines/<hostname>/
│   ├── deploy.sh         # Restore a saved profile to a new machine
│   ├── Brewfile.base     # Shared baseline Homebrew packages
│   └── machines/         # (gitignored) local captures; canonical copy in private/
├── scripts/
│   └── audit/
│       └── security-audit.sh   # Full security posture audit → markdown
├── shell/                # Shared zsh config, aliases, env vars (coming)
├── config/               # App and tool config templates (coming)
└── private/              # Git submodule - per-machine data (not public)
```

---

## Quick Start

### Option A — Homebrew (recommended for quick setup)

Install the hardening tools on any Mac in seconds:

```bash
brew tap davidwhittington/mac-security
brew install davidwhittington/mac-security/mac-security

# Interactive bootstrap — audit + harden in one run
sudo mac-security-first-run

# Or step by step
mac-security-audit --brief
sudo mac-security-harden-ssh
sudo mac-security-firewall

```

| Command | What it does |
|---------|-------------|
| `mac-security-audit` | Full security posture audit — outputs structured Markdown |
| `mac-security-harden-ssh` | Write SSH hardening config, validate, reload sshd |
| `mac-security-firewall` | Enable Application Firewall and stealth mode |
| `mac-security-first-run` | Interactive bootstrap: Homebrew, audit, hardening, re-audit |
| `mac-security-capture` | Snapshot Homebrew packages and shell config |
| `mac-security-deploy` | Restore a saved machine profile to a new Mac |

### Option B — Clone the repo (full workflow with audit history)

```bash
git clone https://github.com/davidwhittington/mac-security.git
cd mac-security
git submodule update --init --recursive   # pulls private/ if you have access

# Print report to stdout
bash scripts/audit/security-audit.sh

# Or save directly into the private submodule
bash scripts/audit/security-audit.sh --save
```

### Capture a machine's environment

```bash
bash pkgs/capture.sh
```

Saves a Brewfile, formula list, cask list, shell config snapshot, and git config to `private/machines/<hostname>/`.

### Deploy to a new or rebuilt machine

```bash
bash pkgs/deploy.sh <hostname-of-source-machine>
```

Installs Homebrew if missing, restores packages from the saved Brewfile, and copies shell config. Backs up any existing files before overwriting.

---

## Security Audit

The audit script checks:

- **Disk encryption** — FileVault on/off
- **System integrity** — SIP, Gatekeeper, Secure Boot
- **Firewall** — Application Firewall state, stealth mode, block-all
- **Sharing services** — SSH, Screen Sharing, Remote Management (ARD), File Sharing, Internet Sharing, Remote Apple Events
- **SSH server config** — PasswordAuthentication, PermitRootLogin, PubkeyAuthentication
- **Open ports** — all TCP listeners via lsof
- **User accounts** — local users, admin group membership
- **macOS updates** — automatic check / download / install policy
- **Installed packages** — full Homebrew formula and cask list

Outputs structured markdown with a **Findings Summary** table that flags issues by severity (Critical / High / Medium).

```bash
# Save report to private/workstations/<hostname>-<date>.md
bash scripts/audit/security-audit.sh --save

# Skip package lists for a faster run
bash scripts/audit/security-audit.sh --brief
```

---

## Workstation Inventory

See [docs/workstations/](docs/workstations/) for the machine inventory table and documentation template.

Per-machine audit reports (with real hostnames, IPs, and findings) are stored in the private submodule - see the section below.

---

## Public / Private Split

Generic scripts and templates live here (public). Machine-specific data - actual audit reports, captured package profiles, network topology - lives in a companion private repo mounted as a git submodule at `private/`.

```
mac-security/          ← public: scripts, templates, guides
└── private/         ← private submodule: per-machine data
    ├── workstations/    audit reports
    └── machines/        captured pkg profiles
```

To adopt this pattern for your own infrastructure:

```bash
gh repo fork davidwhittington/mac-security
gh repo create mac-security-private --private
git submodule add https://github.com/<you>/mac-security-private private/
git commit -m "Add private submodule"
```

---

## Guides

Technical documentation in [docs/guides/](docs/guides/):

- [SSH Pubkey Authentication](docs/guides/ssh-pubkey-auth.md) — set up key-based SSH on a single Mac; disable password auth
- [SSH Fleet Key Management](docs/guides/ssh-fleet-key-management.md) — manage keys across multiple machines; rotation, auditing, ~/.ssh/config
- [Firewall: Application Firewall vs pf](docs/guides/firewall-pf-vs-application-firewall.md) — port-level rules with pf; solving the SSH/block-all conflict
- [Automated Security Drift Detection](docs/guides/automated-security-drift-detection.md) — schedule audits with launchd; alert on security state changes
- [Removing and Disabling Insecure Services](docs/guides/removing-insecure-services.md) — ARD, Screen Sharing, Remote Apple Events, AirDrop; verification and post-update recovery

---

## Security Baseline

See [docs/security/README.md](docs/security/README.md) for the full baseline - required settings, recommended settings, and a reference table of insecure services to audit or remove.

---

## Related

- [mac-tools](https://github.com/davidwhittington/mac-tools) — standalone macOS utilities (tor-proxy, chromium-browse, brew-upgrade, setup-claude)
- [linux-security](https://github.com/davidwhittington/linux-security) — VPS/server security hardening

---

## License

MIT - use freely, adapt for your own lab.
