{ config, lib, pkgs, inputs, ... }:

{
  home-manager = {
    extraSpecialArgs = { inherit inputs; };

    users = {
      "lars" = import ./home-lars.nix;
    };
  };
}