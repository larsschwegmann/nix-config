{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ self, nixpkgs, ... }: {
    # Add hosts to configure here. Its nixosConfigurations.<hostname> as defined in configuration.nix
    nixosConfigurations.mustafar = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./hosts/mustafar/configuration.nix
        ./modules/1password/1password.nix
        ./modules/home-manager/home-manager.nix
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.default
      ];
    };
    nixosConfigurations.endor = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./hosts/endor/configuration.nix
        ./modules/1password/1password.nix
        ./modules/home-manager/home-manager.nix
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.default
      ];
    };
  };
}