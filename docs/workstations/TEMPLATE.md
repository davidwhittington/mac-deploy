# Workstation: `<hostname>`

> Last updated: YYYY-MM-DD | Audited by: `scripts/audit/security-audit.sh`

## Hardware

| Field | Value |
|-------|-------|
| Model | |
| CPU | |
| RAM | |
| Storage | |
| Serial | |
| Role | (dev / build / lab / daily-driver) |

## Software

| Field | Value |
|-------|-------|
| macOS Version | |
| Build | |
| Xcode CLT | |
| Homebrew | |
| Shell | |

---

## Security Posture

### Disk Encryption

| Setting | Status | Notes |
|---------|--------|-------|
| FileVault | ENABLED / DISABLED | |
| Recovery Key Stored | YES / NO | |

### System Integrity

| Setting | Status | Notes |
|---------|--------|-------|
| SIP (System Integrity Protection) | ENABLED / DISABLED | |
| Gatekeeper | ENABLED / DISABLED | |
| Notarization Check | ENABLED / DISABLED | |
| SecureToken | ENABLED / DISABLED | |
| Secure Boot | FULL / MEDIUM / NO SECURITY | |

### Firewall

| Setting | Status | Notes |
|---------|--------|-------|
| Application Firewall | ENABLED / DISABLED | |
| Stealth Mode | ENABLED / DISABLED | |
| Block All Incoming | YES / NO | |

### Remote Access & Sharing

| Service | Status | Notes |
|---------|--------|-------|
| SSH (Remote Login) | ENABLED / DISABLED | |
| Screen Sharing | ENABLED / DISABLED | |
| Remote Management (ARD) | ENABLED / DISABLED | |
| File Sharing | ENABLED / DISABLED | |
| Remote Apple Events | ENABLED / DISABLED | |
| Bluetooth Sharing | ENABLED / DISABLED | |
| Internet Sharing | ENABLED / DISABLED | |
| AirDrop | ENABLED / DISABLED | |

### SSH Configuration

| Setting | Value |
|---------|-------|
| PasswordAuthentication | |
| PermitRootLogin | |
| PubkeyAuthentication | |
| AllowUsers | |
| Port | |

---

## Listening Services & Ports

```
# Output of: sudo lsof -iTCP -sTCP:LISTEN -P -n
# (populated by audit script)
```

## Installed Homebrew Packages

```
# Output of: brew list --formula
# (populated by audit script)
```

## Homebrew Casks

```
# Output of: brew list --cask
# (populated by audit script)
```

---

## Vulnerability Notes

| Finding | Severity | Remediation | Status |
|---------|----------|-------------|--------|
| | | | |

---

## Notes

_Manual observations, anomalies, or follow-up items._
