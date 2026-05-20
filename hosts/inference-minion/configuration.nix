{ config, pkgs, lib, ... }:

{
  imports = [
    ./image.nix
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  networking.hostName = "inference-minion";
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

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
      test -d /var/lib/inference
      test -d /var/lib/inference/models
    '';
  };

  systemd.services.inference-data-grow = {
    description = "Grow INFER_DATA partition and filesystem once";
    wantedBy = [ "multi-user.target" ];
    before = [ "inference-data-ready.service" "ollama.service" "llama-server.service" ];
    after = [ "local-fs.target" ];
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
      partnum="$(lsblk -no PARTN "$part")"
      disk="/dev/$pkname"

      growpart "$disk" "$partnum" || true
      partprobe "$disk"
      udevadm settle
      resize2fs "$part"

      touch "$stamp"
    '';
  };

  services.ollama = {
    enable = true;
    host = "0.0.0.0";
    port = 11434;
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

  systemd.services.llama-server = {
    description = "llama.cpp OpenAI-compatible server";
    after = [ "network-online.target" "inference-data-ready.service" ];
    wants = [ "network-online.target" ];
    requires = [ "inference-data-ready.service" ];
    wantedBy = [ ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.llama-cpp}/bin/llama-server --host 0.0.0.0 --port 8080 --model /var/lib/inference/models/default.gguf";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 11434 ];
  # Keep 8080 closed by default. Open it when enabling llama-server for remote access.

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tmux
    curl
    wget
    llama-cpp
    e2fsprogs
    cloud-utils
    util-linux
  ];

  system.stateVersion = "25.05";
}
