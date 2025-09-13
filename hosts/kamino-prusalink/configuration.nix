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

  networking.hostName = "kamino-prusalink";
  networking.hostId = "2185a8ef";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
    };
  };

  users = {
    users."root" = {
        openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore"
        ];
    };
    users."octoprint".uid = 230;
    groups."octoprint".gid = 230;
  };

  services.octoprint = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    user = "octoprint";
    group = "octoprint";
  };

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    htop
    neofetch
    iperf3
    uv
    python313
  ];


  system.stateVersion = "25.05";
}

