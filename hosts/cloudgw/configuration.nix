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
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/auto-upgrade/auto-upgrade.nix
    ../../modules/nix-cleanup/nix-cleanup.nix
  ];

  custom.autoUpgrade.enable = true;
  custom.nixCleanup.enable = true;

  nix.settings = {
    experimental-features = "nix-command flakes";
  };

  networking.hostName = "cloudgw";
  networking.hostId = "166c038a";

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users = {
    # root.hashedPassword = "!"; # Disable root login
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore"
      ];
    };
    # username = {
    #   isNormalUser = true;
    #   extraGroups = [ "wheel" ];
    #   openssh.authorizedKeys.keys = [
    #     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore"
    #   ];
    # };
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.netdata = {
    enable = true;
  };

  # Agenix secret for WireGuard
  age.secrets.wg-private.file = ../../secrets/cloudgw-wg-private.age;

  # WireGuard tunnel to kamino-http-ingress
  networking.wireguard.interfaces.wg0 = {
    ips = [ "192.168.91.1/30" ];
    listenPort = 51820;
    mtu = 1380;
    privateKeyFile = "/run/agenix/wg-private";
    peers = [{
      publicKey = "DhT9H0bhyfvZFAc57B+AF80mTrEWcklCsGX+VQaKphA=";
      allowedIPs = [ "192.168.91.2/32" ];
    }];
  };

  # Firewall
  networking.firewall.allowedUDPPorts = [ 51820 ];
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # NAT: DNAT ports 80/443 to kamino-http-ingress (no MASQUERADE — preserves client IPs)
  networking.nat = {
    enable = true;
    externalInterface = "enp1s0";
    forwardPorts = [
      { sourcePort = 80;  destination = "192.168.91.2:80";  proto = "tcp"; }
      { sourcePort = 443; destination = "192.168.91.2:443"; proto = "tcp"; }
    ];
  };

  # FORWARD chain rules (NixOS firewall drops forwarded traffic by default)
  networking.firewall.extraCommands = ''
    iptables -A FORWARD -i enp1s0 -o wg0 -p tcp -m multiport --dports 80,443 -j ACCEPT
    iptables -A FORWARD -i wg0 -o enp1s0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i enp1s0 -o wg0 -p tcp -m multiport --dports 80,443 -j ACCEPT || true
    iptables -D FORWARD -i wg0 -o enp1s0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
  '';

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    nano
    wget
    git
    htop
    iperf3
    tmux
    tcpdump
  ];

  system.stateVersion = "25.05";
}
