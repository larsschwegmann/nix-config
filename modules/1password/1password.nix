{ config, lib, pkgs, inputs, ... }:

{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "lars" ];
  };

  environment.etc = {
    # 1Password Browser plugin
    "1Password/custom_allowed_browsers" = {
      text = ''
        firefox
      '';
      mode = "0755";
    };
  };
}