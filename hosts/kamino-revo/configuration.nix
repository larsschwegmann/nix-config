# Revo time tracking (time.0x4c53.net) as a Proxmox LXC.
# The service comes from the private revo-timetracking flake input (services.revo-timetracking);
# TLS terminates on kamino-http-ingress, which forwards to :3000. Setup: docs/kamino-revo.md.

{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:

let
  deployKey = ../../secrets/revo-deploy-key.age;
  hasDeployKey = builtins.pathExists deployKey;
in
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/auto-upgrade/auto-upgrade.nix
    ../../modules/nix-cleanup/nix-cleanup.nix
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

  networking.hostName = "kamino-revo";
  networking.hostId = "9638f078";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # API on 127.0.0.1:8000, web app on :3000 (reached by kamino-http-ingress), local PostgreSQL,
  # nightly pg_dump to /var/backup/revo (14 days). Create the login once:
  #   sudo -u revo revo set-password lars
  services.revo-timetracking = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # Read-only deploy key for the private revo-timetracking repo, so autoUpgrade can fetch the flake
  # input. Off until secrets/revo-deploy-key.age exists (it needs this host's key as a recipient).
  age.secrets = lib.mkIf hasDeployKey { revo-deploy-key.file = deployKey; };
  programs.ssh.extraConfig = lib.mkIf hasDeployKey ''
    Host github.com
      IdentityFile ${config.age.secrets.revo-deploy-key.path}
      IdentitiesOnly yes
  '';
  # GitHub's published host key (https://api.github.com/meta).
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  warnings = lib.optional (!hasDeployKey) "kamino-revo: secrets/revo-deploy-key.age is missing, autoUpgrade can't fetch the revo input (docs/kamino-revo.md)";

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
