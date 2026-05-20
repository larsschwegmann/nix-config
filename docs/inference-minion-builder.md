# inference-minion builder workflow

## Build in single-shot privileged Docker container

Run from repository root:

```bash
docker run --rm -it --privileged --security-opt seccomp=unconfined --platform linux/amd64 \
  -e NIX_CONFIG=$'sandbox = false\nfilter-syscalls = false' \
  -v nix-store-cache:/nix \
  -v "$PWD":/work \
  -w /work \
  nixos/nix bash -lc '
    set -euo pipefail
    mkdir -p /work/results
    out=$(nix --accept-flake-config --extra-experimental-features "nix-command flakes" build --option sandbox false --option filter-syscalls false --no-link --print-out-paths .#packages.x86_64-linux.inference-minion-usb)
    cp -aL "$out" /work/results/inference-minion-usb-image
    ls -lah /work/results
  '
```

Built artifact is copied to `./results/inference-minion-usb-image` on your host filesystem.

Notes:
- `-v nix-store-cache:/nix` persists the Nix store across runs so downloads/build outputs can be reused.
- `--platform linux/amd64` is required on Apple Silicon so the container system matches the flake output system.
- `--accept-flake-config` avoids interactive prompts for trusted caches/keys.
- `--security-opt seccomp=unconfined` plus disabling `sandbox` and `filter-syscalls` avoids seccomp BPF setup failures under Docker Desktop + amd64 emulation on macOS.
- `--no-link` avoids creating `./result` symlinks that point into container-only `/nix/store` paths.
- The warning `Git tree '/work' is dirty` is expected when your repo has uncommitted changes.

If this still fails on your Docker Desktop version, switch to the NixOS VM build path (UTM/Parallels). That path avoids Docker seccomp emulation edge cases entirely.

### Optional: prewarm cache without building image

If you changed only a little and want to hydrate dependencies first:

```bash
docker run --rm -it --privileged --security-opt seccomp=unconfined --platform linux/amd64 \
  -e NIX_CONFIG=$'sandbox = false\nfilter-syscalls = false' \
  -v nix-store-cache:/nix \
  -v "$PWD":/work \
  -w /work \
  nixos/nix bash -lc 'nix --accept-flake-config --extra-experimental-features "nix-command flakes" --option sandbox false --option filter-syscalls false flake show . >/dev/null'
```

## Provision USB on macOS (interactive, recommended)

```bash
./scripts/provision-inference-usb-macos.sh ./results/inference-minion-usb-image
```

What this script does (current script behavior):
- lists disks and prompts for `diskX`
- shows disk details and requires typing `ERASE` confirmation
- flashes the image to the USB
- tries to add an `INFER_DATA` partition as exFAT
- ejects the disk when done

### Important update for current image format

`inference-minion-usb` is now built as a UEFI-safe raw image with partitioning baked in.
The flashed image already contains:

1. `ESP` (vfat)
2. `NIXOS` (ext4, fixed size root)
3. `INFER_DATA` (ext4)

Because `INFER_DATA` is now created in-image as ext4, do **not** add or reformat it as ExFAT.

First boot on the target machine runs a oneshot grow service that expands `INFER_DATA`
to fill the remaining USB space and then resizes the ext4 filesystem.

Until `scripts/provision-inference-usb-macos.sh` is updated for the new layout, prefer the
manual flash flow below and skip any extra partition-creation steps.

## Manual flash fallback

```bash
diskutil list
diskutil unmountDisk /dev/diskX
sudo dd if=./results/inference-minion-usb-image of=/dev/rdiskX bs=4m status=progress
diskutil eject /dev/diskX
```

## Verify layout after first boot

On the inference-minion host after first boot, verify:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
systemctl status inference-data-grow.service --no-pager
systemctl status inference-data-ready.service --no-pager
mount | rg '/var/lib/inference'
```

Expected:
- `ESP` present as vfat
- `NIXOS` root present as ext4
- `INFER_DATA` present as ext4 and expanded to remaining disk space
- `inference-data-grow.service` completed successfully
- `/var/lib/inference` mounted from `INFER_DATA`
