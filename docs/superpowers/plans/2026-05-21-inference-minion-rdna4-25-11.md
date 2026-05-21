# Inference Minion RDNA4 and 25.11 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the fleet baseline to NixOS 25.11 and configure `inference-minion` to use a fresh unstable kernel/graphics/Ollama stack for AMD RX 9070 XT support.

**Architecture:** The fleet continues to use stable NixOS modules from `nixpkgs`; only `inference-minion` pulls GPU-sensitive runtime pieces from `nixpkgs-unstable`. The live USB image remains defined by the existing host configuration and image module.

**Tech Stack:** Nix flakes, NixOS modules, Ollama ROCm, AMDGPU, ROCm, Vulkan diagnostics.

---

## File Structure

- Modify `flake.nix`: update stable `nixpkgs` and `home-manager` input URLs from 25.05 to 25.11.
- Modify `hosts/inference-minion/configuration.nix`: add unstable kernel packages, AMD graphics/ROCm config, and diagnostics tools.
- Update `flake.lock`: refresh changed stable inputs with `nix flake update nixpkgs home-manager` when `nix` is available.

### Task 1: Upgrade Stable Inputs

**Files:**
- Modify: `flake.nix:16-32`

- [ ] **Step 1: Update `nixpkgs` input URL**

Change:

```nix
nixpkgs = {
  url = "github:nixos/nixpkgs/nixos-25.05";
};
```

to:

```nix
nixpkgs = {
  url = "github:nixos/nixpkgs/nixos-25.11";
};
```

- [ ] **Step 2: Update stable `home-manager` input URL**

Change:

```nix
home-manager = {
  url = "github:nix-community/home-manager/release-25.05";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

to:

```nix
home-manager = {
  url = "github:nix-community/home-manager/release-25.11";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

- [ ] **Step 3: Refresh lock file if possible**

Run:

```bash
nix flake update nixpkgs home-manager
```

Expected: `flake.lock` updates the `nixpkgs` and stable `home-manager` nodes. If `nix` is unavailable, leave `flake.lock` unchanged and report that follow-up command.

### Task 2: Add Inference Minion GPU Support

**Files:**
- Modify: `hosts/inference-minion/configuration.nix:12-20`
- Modify: `hosts/inference-minion/configuration.nix:182-195`

- [ ] **Step 1: Add unstable kernel packages**

Insert near the existing boot configuration:

```nix
boot.kernelPackages = unstablePkgs.linuxPackages_latest;
```

- [ ] **Step 2: Enable AMDGPU and graphics runtime support**

Add near firmware/CPU hardware configuration:

```nix
services.xserver.videoDrivers = [ "amdgpu" ];

hardware.graphics = {
  enable = true;
  extraPackages = with unstablePkgs; [
    rocmPackages.clr.icd
    rocmPackages.rocminfo
    rocmPackages.rocm-runtime
  ];
};
```

- [ ] **Step 3: Add diagnostics packages**

Extend `environment.systemPackages` with:

```nix
pciutils
usbutils
clinfo
vulkan-tools
unstablePkgs.rocmPackages.rocminfo
```

### Task 3: Verify Syntax and Buildability

**Files:**
- Verify: `flake.nix`
- Verify: `hosts/inference-minion/configuration.nix`

- [ ] **Step 1: Format check by inspection**

Read the touched Nix files and confirm braces, semicolons, and list syntax are balanced.

- [ ] **Step 2: Evaluate/build if `nix` is available**

Run:

```bash
nixos-rebuild build --flake .#inference-minion
```

Expected: build succeeds or fails with actionable NixOS option/package errors. If `nix` is unavailable, report that local verification could not run.

- [ ] **Step 3: Hardware validation commands for later**

On `inference-minion`, run:

```bash
ls -l /dev/dri
lspci -nn | grep -Ei 'vga|display|amd|ati'
dmesg | grep -Ei 'amdgpu|firmware|drm'
rocminfo
clinfo
journalctl -u ollama -b --no-pager
```

Expected: `/dev/dri` exists, the RX 9070 XT is visible in `lspci`, `amdgpu` initializes without missing firmware errors, ROCm sees an agent, and Ollama logs show GPU backend use.
