# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, inputs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  nix.settings = { sandbox = false; };  
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.hostName = "kamino-immich";
  networking.hostId = "66ac1322";

  security.pam.services.sshd.allowNullPassword = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
    };
  };

  users.users."root".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore"
  ];

  services.immich = {
    enable = true;
    settings = {
      server.externalDomain = "https://immich.schwegmann.me";
      newVersionCheck.enabled = true;
    };
    host = "0.0.0.0";
    port = 2283;
    mediaLocation = "/mnt/immich";
  };

  services.cloudflared = {
    enable = true;
    tunnels = {
      "eb1aee38-be26-42f5-aebe-f4a381b306ef" = {
        credentialsFile = "/root/.cloudflared/eb1aee38-be26-42f5-aebe-f4a381b306ef.json";
        ingress = {
          "immich.schwegmann.me" = "http://localhost:2283";
        };
        default = "http_status:404";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    kitty
    htop
    neofetch
    iperf3
    uv
    python313
  ];


  system.stateVersion = "25.05";
}

