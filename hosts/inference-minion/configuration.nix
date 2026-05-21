{ config, pkgs, lib, inputs, ... }:

let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{

  imports = [
    ./image.nix
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "uas" "sd_mod" ];
  boot.kernelPackages = unstablePkgs.linuxPackages_latest;
  boot.kernelModules = [ "kvm-amd" "amdgpu" ];

  networking.hostName = "inference-minion";
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    package = unstablePkgs.mesa;
    extraPackages = with unstablePkgs; [
      rocmPackages.clr.icd
      rocmPackages.rocminfo
      rocmPackages.rocm-runtime
    ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore"
  ];

  fileSystems."/var/lib/inference" = {
    device = "/dev/disk/by-label/INFER_DATA";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=8s" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/inference 0755 root root -"
    "d /var/lib/inference/ollama 0777 root root -"
    "d /var/lib/inference/ollama-vulkan 0777 root root -"
    "d /var/lib/inference/models 0755 root root -"
    "d /var/lib/inference/logs 0755 root root -"
  ];

  systemd.services.inference-data-ready = {
    description = "Check persistent inference data mount";
    wantedBy = [ "multi-user.target" ];
    after = [ "inference-data-grow.service" ];
    requires = [ "inference-data-grow.service" ];
    before = [ "ollama.service" "llama-server.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      mkdir -p /var/lib/inference/ollama
      mkdir -p /var/lib/inference/ollama-vulkan
      mkdir -p /var/lib/inference/models
      mkdir -p /var/lib/inference/logs
      chmod 0777 /var/lib/inference/ollama /var/lib/inference/ollama-vulkan

      test -d /var/lib/inference
      test -d /var/lib/inference/models
    '';
  };

  systemd.services.inference-data-grow = {
    description = "Grow INFER_DATA partition and filesystem once";
    wantedBy = [ "multi-user.target" ];
    before = [ "inference-data-ready.service" "ollama.service" "llama-server.service" ];
    after = [ "local-fs.target" "systemd-udev-settle.service" ];
    path = with pkgs; [
      coreutils
      gnugrep
      gawk
      e2fsprogs
      cloud-utils
      util-linux
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      stamp="/var/lib/.inference-data-grown"
      if [ -f "$stamp" ]; then
        exit 0
      fi

      part="$(realpath /dev/disk/by-label/INFER_DATA)"
      pkname="$(lsblk -no PKNAME "$part")"
      partnum="$(lsblk -no PARTN "$part" | tr -d '[:space:]')"
      disk="/dev/$pkname"

      if ! [[ "$partnum" =~ ^[0-9]+$ ]]; then
        partnum="$(basename "$part" | sed -E 's/^.*[^0-9]([0-9]+)$/\1/')"
      fi

      if ! [[ "$partnum" =~ ^[0-9]+$ ]]; then
        echo "Could not determine partition number for $part" >&2
        exit 1
      fi

      growpart "$disk" "$partnum" || true
      blockdev --rereadpt "$disk" || true
      udevadm settle
      resize2fs "$part"

      touch "$stamp"
    '';
  };

  services.getty.autologinUser = "root";

  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    port = 11434;
    package = unstablePkgs.ollama-rocm;
  };

  systemd.services.ollama = {
    after = [ "inference-data-ready.service" ];
    requires = [ "inference-data-ready.service" ];
    serviceConfig = {
      ReadWritePaths = lib.mkAfter [
        "/var/lib/inference"
        "/var/lib/inference/ollama"
      ];
      Environment = [
        "OLLAMA_MODELS=/var/lib/inference/ollama"
      ];
    };
  };

  systemd.services.ollama-vulkan = {
    description = "Server for local large language models (Vulkan backend)";
    after = [ "network.target" "inference-data-ready.service" ];
    requires = [ "inference-data-ready.service" ];
    wantedBy = [ ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      StateDirectory = "ollama-vulkan";
      WorkingDirectory = "/var/lib/ollama-vulkan";
      Environment = [
        "OLLAMA_HOST=0.0.0.0:11435"
        "OLLAMA_MODELS=/var/lib/inference/ollama-vulkan"
      ];
      ExecStart = "${unstablePkgs.ollama-vulkan}/bin/ollama serve";
      Restart = "on-failure";
      RestartSec = 5;
      ReadWritePaths = [
        "/var/lib/inference"
        "/var/lib/inference/ollama-vulkan"
      ];
    };
  };

  systemd.services.llama-server = {
    description = "llama.cpp OpenAI-compatible server";
    after = [ "network-online.target" "inference-data-ready.service" ];
    wants = [ "network-online.target" ];
    requires = [ "inference-data-ready.service" ];
    wantedBy = [ ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${unstablePkgs.llama-cpp}/bin/llama-server --host 0.0.0.0 --port 8080 --model /var/lib/inference/models/default.gguf";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 11434 11435 ];
  # Keep 8080 closed by default. Open it when enabling llama-server for remote access.

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tmux
    curl
    wget
    pciutils
    usbutils
    clinfo
    vulkan-tools
    unstablePkgs.llama-cpp
    unstablePkgs.ollama-rocm
    unstablePkgs.ollama-vulkan
    unstablePkgs.rocmPackages.rocminfo
    e2fsprogs
    cloud-utils
    util-linux
  ];

  system.stateVersion = "25.05";
}
