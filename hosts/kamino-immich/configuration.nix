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

  security.pam.services.sshd.allowNullPassword = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
        PermitEmptyPasswords = "yes";
    };
  };

  services.immich = {
    enable = true;
    settings = {
      server.externalDomain = "https://immich.schwegmann.me";
      newVersionCheck.enabled = true;
    };
    port = 2283;
    mediaLocation = "/mnt/immich";
  };


  system.stateVersion = "25.05";
}

