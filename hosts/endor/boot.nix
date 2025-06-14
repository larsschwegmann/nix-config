# Shamelessly stolen from notthebee maya
# https://github.com/notthebee/nix-config/blob/main/machines/nixos/maya/boot.nix
{ lib, pkgs, ... }: 
{
  console = {
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
    keyMap = "de";
  };

  # TTY
  fonts.fonts = [ pkgs.meslo-lgs-nf ];
  services.kmscon = {
    enable = true;
    hwRender = true;
    extraConfig = ''
      font-name=MesloLGS NF
      font-size=20
    '';
  };
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    consoleLogLevel = 0;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
      "boot.shell_on_fail"
    ];
    loader = {
      timeout = 0;
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
    kernelModules = [ "kvm-amd" ];
  };

}