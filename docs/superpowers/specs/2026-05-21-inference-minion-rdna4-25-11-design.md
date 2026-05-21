## Inference Minion RDNA4 GPU Support and 25.11 Upgrade Design

### Goal

Update the fleet baseline from NixOS 25.05 to 25.11 and improve `inference-minion` GPU support for an AMD RX 9070 XT running Ollama from a bootable USB image.

### Approach

Use stable NixOS 25.11 for all hosts. Keep `nixpkgs-unstable` available and use it selectively on `inference-minion` for GPU-sensitive pieces where hardware enablement needs newer kernel/userspace support.

### Flake Inputs

Change the stable inputs:

- `nixpkgs`: `github:nixos/nixpkgs/nixos-25.11`
- `home-manager`: `github:nix-community/home-manager/release-25.11`

Leave `nixpkgs-unstable` and `home-manager-unstable` unchanged.

### Inference Minion GPU Configuration

`inference-minion` will use:

- `unstablePkgs.linuxPackages_latest` for the kernel
- explicit AMDGPU driver selection
- NixOS graphics support via `hardware.graphics.enable`
- ROCm/OpenCL runtime packages from unstable
- diagnostic tools for validating AMDGPU, ROCm, Vulkan, PCI, and OpenCL state after boot

### Ollama Behavior

Continue to run the primary Ollama service using `unstablePkgs.ollama-rocm`.

Do not hardcode `HSA_OVERRIDE_GFX_VERSION` yet. That variable is a workaround for unsupported ROCm GPU detection and should only be added if runtime diagnostics show the RX 9070 XT is detected by the kernel but rejected by ROCm/Ollama userspace.

### Validation

After the patch, validate by updating the lock file and building relevant hosts:

```bash
nix flake update nixpkgs home-manager
nixos-rebuild build --flake .#inference-minion
```

On hardware, validate with:

```bash
ls -l /dev/dri
lspci -nn | grep -Ei 'vga|display|amd|ati'
dmesg | grep -Ei 'amdgpu|firmware|drm'
rocminfo
clinfo
journalctl -u ollama -b --no-pager
```
