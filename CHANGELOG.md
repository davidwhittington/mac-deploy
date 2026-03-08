# Changelog

All notable changes to mac-deploy are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

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
- `private/` — git submodule pointing to `mac-deploy-private` (private companion repo for per-machine data)
- `.gitignore`
