# Workstation Documentation

Each workstation has its own documentation file capturing hardware specs, OS state, installed tools, and security posture.

## Naming Convention

Files are named `<hostname>.md` - use the machine's actual hostname (`hostname` command output).

## How to Document a Machine

1. Run the audit script: `bash scripts/audit/security-audit.sh`
2. Copy output to `docs/workstations/<hostname>.md`
3. Review findings and add manual notes in the **Notes** section
4. Update the inventory table below

## Workstation Inventory

| Hostname | Role | macOS | FileVault | Gatekeeper | SIP | Last Audit |
|----------|------|-------|-----------|------------|-----|------------|
| _(add machines here)_ | | | | | | |

## Template

Use [TEMPLATE.md](TEMPLATE.md) as the starting point for new machine docs.
