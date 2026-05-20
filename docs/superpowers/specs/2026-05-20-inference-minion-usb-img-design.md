## Inference Minion USB Image Design

### Goal

Convert `inference-minion` from an ISO-based installer image to a directly flashable raw `.img` artifact with exactly two partitions:

1. Fixed-size NixOS root partition (ext4)
2. Inference data partition (ext4), auto-resized on first boot to consume all remaining USB space

Target media is a 32 GB USB drive. Root should stay minimal and fixed-size, while model/data capacity should be maximized.

### Current State

- `hosts/inference-minion/image.nix` imports `installer/cd-dvd/installation-cd-minimal.nix`.
- `flake.nix` publishes `packages.x86_64-linux.inference-minion-usb` from `config.system.build.isoImage`.
- `hosts/inference-minion/configuration.nix` mounts `/var/lib/inference` by label `INFER_DATA` as `exfat`.

### Chosen Approach

Approach A (approved): use a native raw disk image build plus first-boot partition/filesystem grow logic.

### Desired End State

#### Build Artifact

- `nix build .#inference-minion-usb` outputs a flashable `.img` (not ISO).

#### Partition Layout

- GPT with exactly two partitions:
  - Partition 1: NixOS system/root, ext4, fixed size **8 GiB**
  - Partition 2: `INFER_DATA`, ext4, fills remainder after first boot resize

#### Runtime Storage Behavior

- `/var/lib/inference` remains mounted by `INFER_DATA` label but with `fsType = "ext4"`.
- Only inference data partition is expanded on first boot.
- Root partition remains fixed-size permanently.

### Implementation Design

#### 1) Image Module Conversion

Update `hosts/inference-minion/image.nix` to import an image-building module that produces a raw disk image rather than ISO installer media.

The image definition must enforce:

- GPT layout
- exactly two partitions
- partition 1 fixed at 8 GiB
- partition 2 labeled `INFER_DATA` and formatted ext4

#### 2) Flake Package Output Switch

Update `flake.nix` package output:

- Replace `config.system.build.isoImage` with the raw image derivation attribute exposed by the selected image module.
- Keep package name `inference-minion-usb` unchanged for stable UX.

#### 3) Filesystem + Mount Update

Update `hosts/inference-minion/configuration.nix`:

- `/var/lib/inference` filesystem:
  - keep `device = "/dev/disk/by-label/INFER_DATA"`
  - change `fsType` from `exfat` to `ext4`
  - remove exfat-only options (`uid/gid/fmask/dmask`)
  - retain resilience options (`nofail`, bounded device timeout)

#### 4) First-Boot Data Partition Expansion

Add a one-shot systemd service in `hosts/inference-minion/configuration.nix` that:

1. Determines the parent disk and partition path for `INFER_DATA`.
2. Expands partition 2 to 100% of available disk.
3. Re-reads partition table and waits for udev settle.
4. Runs `e2fsck -f` and `resize2fs` on partition 2.
5. Writes a stamp file to prevent reruns.

Execution characteristics:

- Runs once per flashed instance.
- Runs before inference services that depend on data mount readiness.
- If resize fails, service failure remains visible and dependent services stay gated.

#### 5) Tooling Requirements

Ensure required utilities are available in the image/runtime for first boot:

- partition editor (for `resizepart`)
- ext4 fs tools (`e2fsck`, `resize2fs`)
- partition table re-read helper and/or udev settle

### Service Ordering and Safety

- `inference-data-ready` continues to guard `ollama`/`llama-server` startup.
- The resize service should complete before those checks to avoid race conditions.
- Resize should be idempotent via a persistent stamp check on root fs for each flashed lifetime.

### Validation Plan

1. Build image: `nix build .#inference-minion-usb`
2. Confirm artifact is raw image (not ISO).
3. Flash to test USB.
4. On first boot, verify:
   - partition 1 remains ~8 GiB
   - partition 2 expands to remaining capacity
   - filesystem on partition 2 is ext4
   - `/var/lib/inference` mounts successfully
5. Verify `ollama` starts after data readiness.

### Out of Scope

- Additional persistent partitions
- Root partition auto-grow
- Live in-place upgrade workflow changes (user will re-image for updates)

### Risks and Mitigations

- **Risk:** Device naming variability (`/dev/sdX` vs `/dev/nvme...`).
  - **Mitigation:** Resolve from partition label path and derive parent disk dynamically.
- **Risk:** Partition table reload race right after resize.
  - **Mitigation:** Explicit reread + udev settle + robust retry loop around block device checks.
- **Risk:** Too-small root partition on future closure growth.
  - **Mitigation:** Start with 8 GiB baseline; adjust to 10-12 GiB later if empirical pressure appears.
