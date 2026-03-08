# mac-deploy

A personal toolkit for deploying, standardizing, and auditing macOS workstations across lab environments. Scripts to capture and restore full machine environments, security posture auditing with markdown output, and shell configuration symmetry across machines.

Designed to be **repeatable and auditable** - run the audit script on any machine and get a consistent, structured report. Capture a working environment and restore it identically elsewhere.

**Tested on:** macOS Sequoia / Tahoe · Apple Silicon (M-series) · zsh

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
mac-deploy/
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

### Audit a machine

Run on any macOS workstation. Outputs a markdown security report:

```bash
git clone https://github.com/davidwhittington/mac-deploy.git
cd mac-deploy
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
mac-deploy/          ← public: scripts, templates, guides
└── private/         ← private submodule: per-machine data
    ├── workstations/    audit reports
    └── machines/        captured pkg profiles
```

To adopt this pattern for your own infrastructure:

```bash
gh repo fork davidwhittington/mac-deploy
gh repo create mac-deploy-private --private
git submodule add https://github.com/<you>/mac-deploy-private private/
git commit -m "Add private submodule"
```

---

## Guides

Technical documentation in [docs/guides/](docs/guides/):

- [SSH Pubkey Authentication](docs/guides/ssh-pubkey-auth.md) — set up key-based SSH across multiple Macs; disable password auth

---

## Security Baseline

See [docs/security/README.md](docs/security/README.md) for the full baseline - required settings, recommended settings, and a reference table of insecure services to audit or remove.

---

## License

MIT - use freely, adapt for your own lab.
