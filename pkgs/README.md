# Package Management & Workstation Re-deployment

Scripts in this directory capture and restore the full software environment of a macOS workstation — Homebrew packages, casks, zsh preferences, and related tooling.

## Workflow

### Capture current machine state

```bash
bash pkgs/capture.sh
```

Saves the current machine's Brewfile, zsh config snapshot, and package lists to `pkgs/machines/<hostname>/`.

### Deploy to a new or rebuilt machine

```bash
bash pkgs/deploy.sh [hostname-profile]
```

Restores Homebrew packages, casks, zsh config, and other tooling from a saved profile.

---

## Files

| File | Purpose |
|------|---------|
| `capture.sh` | Snapshot current machine's packages and shell config |
| `deploy.sh` | Deploy a saved profile to a target machine |
| `Brewfile.base` | Shared base Brewfile for all machines |
| `machines/<hostname>/` | Per-machine captured profiles |
