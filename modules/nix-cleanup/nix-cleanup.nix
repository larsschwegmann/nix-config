{ config, lib, ... }:

let
  cfg = config.custom.nixCleanup;
in
{
  options.custom.nixCleanup = {
    enable = lib.mkEnableOption "automatic nix store garbage collection and optimisation";

    olderThan = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Delete generations older than this age.";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "systemd calendar expression for when to run garbage collection.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.gc = {
      automatic = true;
      dates = cfg.dates;
      options = "--delete-older-than ${cfg.olderThan}";
    };

    nix.optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };
}
