# Hoard Sync (sync.hoardapp.dev, sync-staging.hoardapp.dev) as a Proxmox LXC.
# Only the LXC specifics live here; the service itself is modules/hoard-sync.
# Setup and moving to Hetzner: ops/ in the private hoardapp repo.

{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/auto-upgrade/auto-upgrade.nix
    ../../modules/nix-cleanup/nix-cleanup.nix
    ../../modules/hoard-sync/hoard-sync.nix
  ];

  custom.autoUpgrade.enable = true;
  custom.nixCleanup.enable = true;
  nix.settings = {
    sandbox = false;
  };
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.hostName = "kamino-hoard-sync";
  networking.hostId = "8eafaff7";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # TLS terminates on kamino-http-ingress, which forwards to :8080 (prod) and :8081 (staging).
  custom.hoardSync = {
    enable = true;
    tls = "external";
    trustedProxy = "192.168.36.123";
    appStoreApiKey = true;
  };

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

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    htop
    tmux
  ];

  system.stateVersion = "25.11";
}
