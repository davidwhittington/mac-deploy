# Changelog

All notable changes to mac-security are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [0.8.0] - 2026-03-09

### Changed
- **Project renamed from `mac-security` to `mac-security`** — better reflects the security-first focus of the toolkit (hardening, auditing, config management, and future virtualization). This is a breaking change for existing Homebrew users: `brew upgrade mac-security` will install new command names.
- All commands renamed: `mac-security-*` → `mac-security-*` (13 commands)
- Homebrew tap renamed: `davidwhittington/mac-security` → `davidwhittington/mac-security` (tap repo: `homebrew-mac-security`)
- Plist identifiers updated: `com.mac-security.*` → `com.mac-security.*`
- pf anchor renamed: `/etc/pf.anchors/mac-security` → `/etc/pf.anchors/mac-security`
- Output paths updated: `~/.zshrc-mac-security` → `~/.zshrc-mac-security`; temp and log paths
- Private submodule repo renamed: `mac-security-private` → `mac-security-private`

---

## [0.7.0] - 2026-03-09

### Added
- `scripts/brew-upgrade.sh` — Homebrew upgrade with change logging: `brew update` → captures outdated list → `brew upgrade` → `brew cleanup`; logs dated summary to `private/machines/<hostname>/brew-upgrades.log`; supports `--dry-run`, `--no-casks`
- `scripts/apply-defaults.sh` — macOS system preferences hardening: screen lock (password required immediately, 5-min idle), screenshot redirect, Finder settings, AirDrop contacts-only, Mail remote content blocking, Safari security settings, Software Update policy; supports `--dry-run`

### Changed
- `scripts/audit/security-audit.sh` — four new security checks:
  - Bluetooth state via `system_profiler` (Medium finding if on)
  - Developer mode via `DevToolsSecurity` (Medium finding if enabled)
  - World-readable files in `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/op` (High finding)
  - Sudoers NOPASSWD entries in `/etc/sudoers` and `/etc/sudoers.d/` (High finding)
  - New sections: Sensitive File Permissions, Sudoers Configuration

---

## [0.6.0] - 2026-03-09

### Added
- `scripts/apply-configs.sh` — application config templating engine: renders `${VAR}` placeholders in templates using layered settings files, diffs against existing destinations, backs up before writing; SSH config safety guard prevents silent overwrites; supports `--dry-run`, `--list`, `--manifest`, `--machine`
- `configs/templates/git/gitconfig.tmpl` — git config template: name, email, editor, default branch, credential helper, aliases, color output
- `configs/templates/ssh/config.tmpl` — SSH client config template: ControlMaster, keepalive, key path, lab host blocks
- `configs/templates/zsh/zshrc-base.tmpl` — zsh base config: history, completion, Homebrew init, Starship or fallback prompt, common aliases, local override sourcing
- `configs/templates/starship/starship.toml.tmpl` — Starship prompt config: git branch/status, command duration, hostname
- `configs/settings/defaults.env` — base variable values; override per machine via `private/machines/<hostname>/configs.env`
- `configs/manifests/default.conf` — default template-to-destination mapping; customizable per machine

---

## [0.5.0] - 2026-03-08

### Added
- `scripts/harden-sshd.sh` — applies SSH hardening config to `/etc/ssh/sshd_config.d/099-hardening.conf`; validates with `sshd -t`, reloads sshd if active; supports `--dry-run`
- `scripts/enable-stealth-firewall.sh` — enables Application Firewall and stealth mode; `--with-pf` configures a pf anchor (allow port 22, block all other inbound) with LaunchDaemon persistence; supports `--dry-run`
- `scripts/first-run.sh` — interactive bootstrap for a new Mac: installs Homebrew, taps mac-security, runs audit, applies SSH and firewall hardening, re-audits to confirm baseline; supports `--auto` and `--audit-only`
- GitHub Pages landing page (`index.html`) — dark-themed intro with quick start, feature overview, commands, and guide links
- Homebrew tap (`davidwhittington/homebrew-mac-security`) — `brew tap davidwhittington/mac-security && brew install mac-security` installs all six commands

### Changed
- `README.md` — Homebrew tap as primary install method; command table; link to website

---

## [0.4.0] - 2026-03-08

### Added
- `docs/guides/removing-insecure-services.md` — step-by-step disabling of ARD, Screen Sharing, Remote Apple Events, Internet Sharing, File Sharing, Bluetooth Sharing, Wake for Network Access, and AirDrop; includes per-service launchctl verification, post-update re-enable detection, and a full one-shot checklist script

### Changed
- `docs/guides/README.md` — added new guide to index
- `README.md` — added new guide to Guides section

---

## [0.3.0] - 2026-03-08

### Added
- `docs/guides/firewall-pf-vs-application-firewall.md` — Application Firewall vs pf deep dive: stealth mode, block-all tradeoffs, pf anchor setup, LaunchDaemon for persistence, recommended lab config
- `docs/guides/ssh-fleet-key-management.md` — SSH key management across a lab fleet: per-client key strategy, naming conventions, ~/.ssh/config host blocks, fleet deployment script, key rotation workflow, authorized_keys audit script
- `docs/guides/automated-security-drift-detection.md` — launchd-based scheduled auditing: drift detection via report diff, system log integration, LaunchAgent plist, audit history in private submodule
- `scripts/audit/scheduled-audit.sh` — wrapper script for launchd; runs audit, diffs against previous report, logs drift to private submodule and macOS system log

### Changed
- `docs/guides/README.md` — updated guide index with all four guides
- `README.md` — updated Guides section with all four guides

---

## [0.2.0] - 2026-03-08

### Added
- `docs/guides/ssh-pubkey-auth.md` — full walkthrough for key-based SSH across macOS machines: key generation, authorized_keys setup, sshd hardening, multi-machine deployment, and troubleshooting
- `docs/guides/README.md` — guide index
- `LICENSE` — MIT
- `CHANGELOG.md`
- Polished README aligned with vps-hardening style — background, feature table, quick start, public/private submodule pattern

### Changed
- `scripts/audit/security-audit.sh` — fixed multiple `set -e` fragility issues: Secure Boot bputil, SSH state detection, grep calls in findings loop, `$DATE_` typo; added `--save` flag to write report directly to `private/workstations/`
- `pkgs/capture.sh` — redirected output from `pkgs/machines/` to `private/machines/` (private submodule)
- `.gitignore` — removed `private/` exclusion (now a tracked submodule)

---

## [0.1.0] - 2026-03-08

### Added
- `scripts/audit/security-audit.sh` — full macOS security posture audit: FileVault, SIP, Gatekeeper, Secure Boot, Application Firewall, sharing services, SSH config, open ports, user accounts, Homebrew packages, macOS update policy; outputs structured markdown with Findings Summary table
- `docs/workstations/TEMPLATE.md` — per-machine documentation template
- `docs/workstations/README.md` — machine inventory table
- `docs/security/README.md` — security baseline policy, insecure service reference, findings tracker
- `pkgs/capture.sh` — snapshot Homebrew packages, shell config, git config, SSH key list, macOS defaults from current machine
- `pkgs/deploy.sh` — restore a saved machine profile: Homebrew via Brewfile, shell config, git config
- `pkgs/Brewfile.base` — shared baseline Homebrew packages for all lab machines
- `private/` — git submodule pointing to `mac-security-private` (private companion repo for per-machine data)
- `.gitignore`
