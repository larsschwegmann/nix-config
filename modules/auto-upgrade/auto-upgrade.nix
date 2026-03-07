{ config, lib, ... }:

let
  cfg = config.custom.autoUpgrade;
in
{
  options.custom.autoUpgrade = {
    enable = lib.mkEnableOption "automatic NixOS upgrades from the flake";

    dates = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "systemd calendar expression for when to run the upgrade.";
    };

    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow automatic reboots after upgrades.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Random delay added to the timer to stagger rebuilds across hosts.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = "github:larsschwegmann/nix-config#${config.networking.hostName}";
      dates = cfg.dates;
      allowReboot = cfg.allowReboot;
      randomizedDelaySec = cfg.randomizedDelaySec;
    };
  };
}
