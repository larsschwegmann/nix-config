{ modulesPath, lib, config, pkgs, ... }:

{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  image.repart.name = "inference-minion";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.efi.efiSysMountPoint = "/boot";

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  image.repart.partitions = {
    "10-esp" = {
      contents = {
        "/EFI/BOOT/BOOTX64.EFI".source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
      };
      repartConfig = {
        Type = "esp";
        Format = "vfat";
        Label = "ESP";
        SizeMinBytes = "512M";
        SizeMaxBytes = "512M";
      };
    };

    "20-root" = {
      storePaths = [ config.system.build.toplevel ];
      repartConfig = {
        Type = "root-x86-64";
        Format = "ext4";
        Label = "NIXOS";
        SizeMinBytes = "8G";
        SizeMaxBytes = "8G";
      };
    };

    "30-infer-data" = {
      repartConfig = {
        Type = "home";
        Format = "ext4";
        Label = "INFER_DATA";
        SizeMinBytes = "1G";
      };
    };
  };
}
