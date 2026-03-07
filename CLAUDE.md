# Nix Config

Flake-based NixOS configuration managing multiple hosts. All hosts are x86_64-linux. Uses nixpkgs 25.05 (stable) with an unstable channel available.

## Repository Structure

```
flake.nix              # Entry point — defines all hosts and flake inputs
hosts/<hostname>/      # Per-host config (configuration.nix, hardware-configuration.nix)
modules/               # Reusable NixOS modules with custom.* option namespace
```

## Hosts

| Host | Role | Platform |
|------|------|----------|
| **cloudgw** | Gateway/network server | Bare metal or VM |
| **mustafar** | Desktop workstation (GNOME, home-manager, 1Password, disko) | Bare metal |
| **kamino-immich** | Immich photo service | Proxmox LXC container |
| **kamino-prusalink** | PrusaLink 3D printer integration | Proxmox LXC container |
| **kamino-http-ingress** | HTTP reverse proxy/ingress | Proxmox LXC container |

The `kamino-*` hosts are Proxmox LXC containers (privileged, `sandbox = false`). `mustafar` is the only desktop host and uses home-manager for user-level config.

## Custom Modules

Modules live in `modules/` and follow the `custom.*` option pattern with `enable` toggles:

- **`custom.autoUpgrade`** — Auto-rebuild from `github:larsschwegmann/nix-config` on a schedule
- **`custom.nixCleanup`** — Periodic nix store garbage collection and optimisation
- **`modules/1password/`** — 1Password GUI + browser integration (imported directly, no enable toggle)

All server hosts enable `autoUpgrade` and `nixCleanup`.

## Key Commands

```bash
# Build and switch locally (run on the target host)
sudo nixos-rebuild switch --flake .#<hostname>

# Build without switching (dry run)
nixos-rebuild build --flake .#<hostname>

# Update flake inputs
nix flake update
```

## Automation

- **GitHub Actions** (`.github/workflows/update-flake-lock.yml`): Automatically updates `flake.lock` and creates a PR
- **Auto-upgrade**: Hosts with `custom.autoUpgrade.enable = true` pull from the GitHub flake and rebuild on a timer (default 04:00, with 30min random delay)
- **Nix cleanup**: Hosts with `custom.nixCleanup.enable = true` run weekly GC (delete generations >30d) and store optimisation

## Flake Inputs

- `nixpkgs` (nixos-25.05) / `nixpkgs-unstable`
- `home-manager` (release-25.05) / `home-manager-unstable`
- `disko` — declarative disk partitioning (used by mustafar)
- Binary caches: cachix, nixpkgs, nix-community
