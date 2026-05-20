# Inference Minion USB IMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a directly flashable `inference-minion` `.img` with two partitions where root stays fixed at 8 GiB and `INFER_DATA` (ext4) auto-expands to remaining USB space on first boot.

**Architecture:** Replace the ISO installer module with a raw image module, configure partitioning/image attributes for a two-partition GPT layout, and change the flake package output to the raw image derivation. In host config, switch `/var/lib/inference` to ext4 and add a one-shot resize service that grows partition 2 and its filesystem exactly once.

**Tech Stack:** NixOS modules, nixpkgs image modules (`sd-image`), systemd oneshot service, GNU parted, e2fsprogs, util-linux/udev tooling.

---

## File Structure

- Modify: `hosts/inference-minion/image.nix`
  - Responsibility: switch from ISO installer module to raw image module and define image partition sizing defaults.
- Modify: `hosts/inference-minion/configuration.nix`
  - Responsibility: ext4 data mount and first-boot partition/filesystem auto-grow service.
- Modify: `flake.nix`
  - Responsibility: expose the `.img` build artifact under existing package name `inference-minion-usb`.

### Task 1: Convert inference-minion image from ISO to raw IMG

**Files:**
- Modify: `hosts/inference-minion/image.nix`
- Test: build check via `nix build .#inference-minion-usb`

- [ ] **Step 1: Write the failing check command (current config should not expose IMG output)**

```bash
nix build .#inference-minion-usb
```

Expected: build output path corresponds to ISO artifact usage from `system.build.isoImage` and not a raw sd-image derivation.

- [ ] **Step 2: Replace image module content with raw image module configuration**

```nix
{ modulesPath, lib, ... }:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  # Keep compression disabled for a directly flashable artifact.
  sdImage.compressImage = false;

  # Root should remain small and fixed; data partition will consume remaining space after first boot.
  sdImage.imageBaseName = "inference-minion";
  sdImage.firmwareSize = 0;
  sdImage.rootPartitionSize = 8 * 1024;

  # We are not producing Raspberry Pi firmware partitions.
  boot.loader.grub.enable = lib.mkDefault true;
}
```

- [ ] **Step 3: Run formatter/check for Nix syntax validity**

```bash
nix-instantiate --parse hosts/inference-minion/image.nix
```

Expected: command succeeds and prints parsed Nix expression.

- [ ] **Step 4: Commit task changes**

```bash
git add hosts/inference-minion/image.nix
git commit -m "feat(inference-minion): switch image module to raw sd-image"
```

### Task 2: Switch flake package output from ISO to IMG derivation

**Files:**
- Modify: `flake.nix`
- Test: `nix build .#inference-minion-usb`

- [ ] **Step 1: Write failing check for expected package output attribute**

```bash
nix eval .#nixosConfigurations.inference-minion.config.system.build.isoImage.drvPath
```

Expected: currently succeeds, confirming flake is still tied to ISO flow.

- [ ] **Step 2: Update package output to raw image derivation**

```nix
    packages.x86_64-linux.inference-minion-usb =
      self.nixosConfigurations.inference-minion.config.system.build.sdImage;
```

- [ ] **Step 3: Verify new package can evaluate**

```bash
nix eval .#packages.x86_64-linux.inference-minion-usb.drvPath
```

Expected: succeeds and resolves to an `sdImage` derivation path.

- [ ] **Step 4: Commit task changes**

```bash
git add flake.nix
git commit -m "feat(flake): publish inference-minion raw usb image"
```

### Task 3: Migrate inference data mount from exfat to ext4

**Files:**
- Modify: `hosts/inference-minion/configuration.nix`
- Test: `nix-instantiate --parse hosts/inference-minion/configuration.nix`

- [ ] **Step 1: Capture existing mount block as failing expectation basis**

```bash
rg -n 'fileSystems."/var/lib/inference"|fsType = "exfat"|fmask|dmask' hosts/inference-minion/configuration.nix
```

Expected: shows `fsType = "exfat"` and exfat-specific mount options.

- [ ] **Step 2: Replace mount block with ext4-safe configuration**

```nix
  fileSystems."/var/lib/inference" = {
    device = "/dev/disk/by-label/INFER_DATA";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=8s" ];
  };
```

- [ ] **Step 3: Verify no exfat-specific options remain**

```bash
rg -n 'fsType = "exfat"|fmask|dmask|uid=0|gid=0' hosts/inference-minion/configuration.nix
```

Expected: no matches.

- [ ] **Step 4: Commit task changes**

```bash
git add hosts/inference-minion/configuration.nix
git commit -m "feat(inference-minion): use ext4 inference data partition"
```

### Task 4: Add one-shot first-boot service to grow INFER_DATA partition and ext4 filesystem

**Files:**
- Modify: `hosts/inference-minion/configuration.nix`
- Test: `nix build .#inference-minion-usb`

- [ ] **Step 1: Add required tools to system packages for first-boot grow workflow**

```nix
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tmux
    curl
    wget
    llama-cpp
    parted
    e2fsprogs
    util-linux
  ];
```

- [ ] **Step 2: Add auto-grow one-shot systemd service**

```nix
  systemd.services.inference-data-grow = {
    description = "Grow INFER_DATA partition and ext4 filesystem on first boot";
    wantedBy = [ "multi-user.target" ];
    before = [ "inference-data-ready.service" "ollama.service" "llama-server.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      coreutils
      gnugrep
      gawk
      parted
      e2fsprogs
      util-linux
      systemd
    ];
    script = ''
      set -euo pipefail

      stamp=/var/lib/.inference-data-grown
      if [ -f "$stamp" ]; then
        exit 0
      fi

      part="$(readlink -f /dev/disk/by-label/INFER_DATA)"
      disk="$(lsblk -no PKNAME "$part")"
      disk="/dev/$disk"

      parted -s "$disk" resizepart 2 100%
      partprobe "$disk"
      udevadm settle

      e2fsck -f -y "$part"
      resize2fs "$part"

      touch "$stamp"
    '';
  };
```

- [ ] **Step 3: Ensure readiness gate runs after grow service**

```nix
  systemd.services.inference-data-ready = {
    description = "Check persistent inference data mount";
    wantedBy = [ "multi-user.target" ];
    before = [ "ollama.service" "llama-server.service" ];
    after = [ "inference-data-grow.service" ];
    requires = [ "inference-data-grow.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      test -d /var/lib/inference/ollama
      test -d /var/lib/inference/models
    '';
  };
```

- [ ] **Step 4: Build and validate final artifact type**

Run: `nix build .#inference-minion-usb`

Expected:
- Build succeeds
- `result/` points to sd-image output
- Artifact is `.img` (or `.img`-named output) and not ISO

- [ ] **Step 5: Commit task changes**

```bash
git add hosts/inference-minion/configuration.nix
git commit -m "feat(inference-minion): auto-grow inference data partition on first boot"
```

### Task 5: End-to-end validation on real USB media

**Files:**
- No repository file changes
- Test: runtime validation commands on target host

- [ ] **Step 1: Flash image to USB media**

Run (example):

```bash
sudo dd if=result/inference-minion.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Expected: write completes without I/O errors.

- [ ] **Step 2: Boot inference-minion from flashed USB and inspect partitions**

Run:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
```

Expected:
- partition 1 ext4 around 8 GiB
- partition 2 ext4 labeled `INFER_DATA`, expanded to remainder of device

- [ ] **Step 3: Verify first-boot grow service result**

Run:

```bash
systemctl status inference-data-grow.service --no-pager
```

Expected: `active (exited)` with successful completion.

- [ ] **Step 4: Verify inference data mount and dependent service readiness**

Run:

```bash
mount | rg '/var/lib/inference'
systemctl status inference-data-ready.service --no-pager
systemctl status ollama.service --no-pager
```

Expected:
- `/var/lib/inference` mounted from `INFER_DATA` as ext4
- readiness service successful
- `ollama` running (or started successfully)

- [ ] **Step 5: Commit validation notes (optional, if tracked)**

```bash
git status
```

Expected: no unintended repo changes after runtime validation.
