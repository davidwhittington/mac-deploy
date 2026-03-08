# Security Documentation

## Baseline Security Policy

All lab workstations should meet the following minimum security baseline:

### Required (Critical)

- [ ] **FileVault enabled** — full disk encryption on all machines
- [ ] **SIP enabled** — System Integrity Protection must not be disabled
- [ ] **Gatekeeper enabled** — block unsigned/unnotarized software
- [ ] **Application Firewall enabled** — with stealth mode on
- [ ] **SSH PasswordAuthentication disabled** — key-based auth only
- [ ] **PermitRootLogin disabled** — no direct root SSH
- [ ] **Screen Sharing / Remote Management disabled** — unless explicitly needed

### Recommended (High)

- [ ] **Secure Boot: Full Security** — on Apple Silicon and T2 machines
- [ ] **Automatic macOS updates enabled** — security patches applied promptly
- [ ] **Guest account disabled**
- [ ] **FileVault recovery key backed up securely** — not stored on-device
- [ ] **SSH on non-standard port** — reduce automated scan exposure

### Optional (Medium)

- [ ] **Stealth mode enabled** on firewall
- [ ] **Block all incoming** enabled on networks you don't control
- [ ] **AirDrop set to Contacts Only or Off** in untrusted environments
- [ ] **Bluetooth off** when not in use on lab/server machines

---

## Known Vulnerabilities & Findings

See individual workstation docs in [../workstations/](../workstations/) for per-machine findings.

| Machine | Finding | Severity | Opened | Resolved |
|---------|---------|----------|--------|----------|
| | | | | |

---

## Insecure Services to Audit / Remove

The following services are commonly left enabled and represent unnecessary attack surface:

| Service | Risk | How to Disable |
|---------|------|---------------|
| Remote Apple Events | Medium — allows AppleScript execution over network | System Settings → Sharing → uncheck |
| Bluetooth Sharing | Low-Medium | System Settings → Sharing → uncheck |
| Internet Sharing | High — can expose network | System Settings → Sharing → uncheck |
| Wake for network access | Low-Medium | System Settings → Battery → uncheck |
| Remote Management (ARD) | High — full screen/keyboard control | `sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate` |
| mDNSResponder broadcasts | Low | Not typically disabled, but monitor |
| tftp / ftp | High — if running | `sudo launchctl unload -w /System/Library/LaunchDaemons/tftp.plist` |

---

## References

- [macOS Security Compliance Project (mSCP)](https://github.com/usnistgov/macos_security)
- [CIS Benchmark for macOS](https://www.cisecurity.org/benchmark/apple_os)
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web)
