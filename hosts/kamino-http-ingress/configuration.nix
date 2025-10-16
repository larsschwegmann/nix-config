# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];
  nix.settings = {
    sandbox = false;
  };
  proxmoxLXC = {
    manageNetwork = false;
    privileged = true;
  };

  networking.hostName = "kamino-http-ingress";
  networking.hostId = "3a11c6dc";

  # security.pam.services.sshd.allowNullPassword = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  ###############################

  # ACME config
  security.acme = {
    acceptTerms = true;
    defaults.email = "info@0x4c53.net";

    certs."0x4c53.net" = {
      domain = "0x4c53.net";
      extraDomainNames = [ "*.0x4c53.net" ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      credentialsFile = /etc/secrets/acme/cloudflare.ini;
    };
  };

  # Traefik
  users.users.traefik.extraGroups = [ "acme" ];
  services.traefik = {
    enable = true;
    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };

      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entrypoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure = {
          address = ":443";
        };

      };
      # providers.docker.exposedByDefault = false;
    };
    dynamicConfigOptions = {
      tls = {
        stores.default = {
          defaultCertificate = {
            certFile = "/var/lib/acme/0x4c53.net/cert.pem";
            keyFile = "/var/lib/acme/0x4c53.net/key.pem";
          };
        };

        certificates = [
          {
            certFile = "/var/lib/acme/0x4c53.net/cert.pem";
            keyFile = "/var/lib/acme/0x4c53.net/key.pem";
            stores = "default";
          }
        ];
      };

      http.routers.jellyfin = {
        rule = "Host(`jellyfin.0x4c53.net`)";
        entryPoints = [ "websecure" ];
        service = "jellyfin";
        tls = {
          domains = {
            main = [ "0x4c53.net" ];
            sans = [ "*.0x4c53.net" ];
          };
        };
      };

      http.services.jellyfin = {
        loadBalancer.servers = [
          {
            url = "http://10.0.2.69:8096";
          }
        ];
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  #####################

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
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    nano
    wget
    git
    htop
    iperf3
  ];

  system.stateVersion = "25.05";
}
