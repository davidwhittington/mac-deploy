# mac-deploy

Private repository for managing macOS workstation deployment, development environment standardization, and shell customization across lab machines.

## Purpose

- **Deployment scripts** — automate setup of new/rebuilt workstations
- **Dev environment standardization** — consistent tooling, paths, and config across machines
- **Shell symmetry** — shared zsh config, aliases, and environment vars
- **Security documentation** — capture and track security posture of all workstations

## Repository Structure

```
mac-deploy/
├── docs/
│   ├── workstations/     # Per-machine state documentation
│   ├── security/         # Security policies, posture assessments
│   ├── network/          # Network topology, services
│   └── services/         # Service inventory and notes
├── scripts/
│   ├── audit/            # Security and state audit scripts
│   ├── setup/            # Initial machine setup scripts
│   └── deploy/           # Deployment automation
├── shell/
│   ├── zsh/              # Shared zshrc components
│   ├── aliases/          # Shared alias files
│   └── env/              # Shared environment variables
└── config/               # App and tool config templates
```

## Workstation Inventory

See [docs/workstations/](docs/workstations/) for individual machine documentation.

## Security Auditing

Run the audit script on any machine to generate a security posture report:

```bash
bash scripts/audit/security-audit.sh > docs/workstations/<hostname>-audit.md
```

See [docs/security/](docs/security/) for security baseline and findings.
