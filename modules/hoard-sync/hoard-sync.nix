# Hoard Sync (sync.hoardapp.dev + sync-staging.hoardapp.dev): everything except "where am I running".
#
# Bundles the two server instances (from the private hoardapp flake input), Garage as the S3 store,
# Postgres for the control plane, hourly pg_dump and continuous Litestream replication into Garage,
# the firewall and the agenix secrets. A host only sets enable, tls and trustedProxy, so moving to
# another machine (ops/hoard-sync-migration.md in the private hoardapp repo) is a new host file plus re-encrypted secrets.
#
# The host flake must also import inputs.hoard.nixosModules.hoard-sync and
# inputs.agenix.nixosModules.default. Setup: ops/ in the private hoardapp repo.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.custom.hoardSync;

  # Litestream 0.5 (directory replication) isn't in nixos-25.11, which has 0.3.
  pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  instances = {
    prod = {
      port = 8080;
      domain = "sync.hoardapp.dev";
      # App Review and TestFlight purchase in the sandbox, so production accepts both.
      environments = [
        "Production"
        "Sandbox"
      ];
    };
    staging = {
      port = 8081;
      domain = "sync-staging.hoardapp.dev";
      environments = [ "Sandbox" ];
    };
  };

  # The system user, Postgres role and database of an instance (see hoardapp's nix/module.nix).
  dbName = name: "hoard_${name}";
  stateDir = name: "/var/lib/hoard-sync/${name}";

  garageS3 = "http://127.0.0.1:3900";
  garageRegion = "garage";
  pgBackupBucket = "hoard-pg-backups";

  secret = name: {
    file = ../../secrets/${name}.age;
  };
  secretPath = name: config.age.secrets.${name}.path;
in
{
  options.custom.hoardSync = {
    enable = lib.mkEnableOption "the Hoard sync service (prod + staging, Garage, Postgres, Litestream)";

    tls = lib.mkOption {
      type = lib.types.enum [
        "external"
        "builtin"
      ];
      default = "external";
      description = ''
        `external`: a reverse proxy on another host (kamino-http-ingress) terminates TLS and
        forwards plain HTTP to the instance ports, which only that proxy may reach.
        `builtin`: a standalone host (a Hetzner VM) gets its own ACME certificate (Cloudflare DNS-01)
        and a local Traefik on 80/443.
      '';
    };

    trustedProxy = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "192.168.36.123";
      description = ''
        With tls = "external": the reverse proxy's IP. Only it may reach the instance ports, and
        only its X-Forwarded-* headers are trusted. Ignored with tls = "builtin".
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      default = "info@0x4c53.net";
      description = "ACME account e-mail (tls = \"builtin\" only).";
    };

    appStoreApiKey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Give the instances the In-App Purchase API key (secrets/hoard-sync-appstore-key.age) for the
        daily reconciliation. Turn on once that file exists; its key id and issuer id go into the
        instances' env secrets.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        ######## Secrets (agenix; encrypted to lars + the host key, see secrets/secrets.nix) ########

        age.secrets = {
          # Read-only deploy key for the private hoardapp repo, so autoUpgrade can fetch the flake input.
          hoardapp-deploy-key = secret "hoardapp-deploy-key";
          # GARAGE_RPC_SECRET, GARAGE_ADMIN_TOKEN
          hoard-sync-garage-env = secret "hoard-sync-garage-env";
          # HOARD_ADMIN_PASSWORD, HOARD_S3_KEY_ID, HOARD_S3_SECRET, HOARD_APPLE_APP_ID (prod: required, as
          # prod accepts Production) [, HOARD_APPSTORE_KEY_ID, HOARD_APPSTORE_ISSUER_ID]
          hoard-sync-prod-env = secret "hoard-sync-prod-env";
          hoard-sync-staging-env = secret "hoard-sync-staging-env";
          # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY of the Garage key for Litestream and pg_dump uploads
          hoard-sync-backup-env = secret "hoard-sync-backup-env";
        }
        // lib.optionalAttrs cfg.appStoreApiKey {
          hoard-sync-appstore-key = secret "hoard-sync-appstore-key";
        };

        # Nix fetches git+ssh://git@github.com/larsschwegmann/hoardapp with the system ssh config.
        programs.ssh.extraConfig = ''
          Host github.com
            IdentityFile ${secretPath "hoardapp-deploy-key"}
            IdentitiesOnly yes
        '';
        # GitHub's published host key (https://api.github.com/meta).
        programs.ssh.knownHosts."github.com".publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

        ######## The sync server instances ########

        services.hoard-sync = {
          listenAddress = if cfg.tls == "external" then "0.0.0.0" else "127.0.0.1";
          trustedProxy = if cfg.tls == "external" then cfg.trustedProxy else "127.0.0.1";
          instances = lib.mapAttrs (name: instance: {
            inherit (instance) port environments;
            publicUrl = "https://${instance.domain}";
            billing = "apple";
            s3 = {
              endpoint = garageS3;
              region = garageRegion;
              bucket = "hoard-${name}-blobs";
            };
            databaseUrl = "postgresql:///${dbName name}?host=/run/postgresql";
            secretsFile = secretPath "hoard-sync-${name}-env";
            # HOARD_APPLE_APP_ID comes from the env secret, so it can be filled in without a commit.
            apple = {
              appStoreKeyFile = if cfg.appStoreApiKey then secretPath "hoard-sync-appstore-key" else null;
            };
          }) instances;
        };

        # Litestream watches realms/ from the start, before the first realm exists.
        systemd.tmpfiles.rules = lib.mapAttrsToList (
          name: _: "d ${stateDir name}/realms 0770 ${dbName name} ${dbName name} -"
        ) instances;

        ######## Garage: single-node S3, API on localhost only ########
        # Buckets and keys are created once by hand (ops/hoard-sync-setup.md in the private hoardapp repo).

        services.garage = {
          enable = true;
          package = pkgs.garage_2;
          environmentFile = secretPath "hoard-sync-garage-env";
          settings = {
            replication_factor = 1;
            db_engine = "sqlite";
            rpc_bind_addr = "127.0.0.1:3901";
            rpc_public_addr = "127.0.0.1:3901";
            s3_api = {
              api_bind_addr = "127.0.0.1:3900";
              s3_region = garageRegion;
            };
            admin.api_bind_addr = "127.0.0.1:3903";
          };
        };

        ######## Postgres 17: the control plane, unix socket + peer auth only ########
        # Pinned: a major upgrade is a deliberate pg_upgrade, never a side effect of a nixpkgs bump.

        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_17;
          ensureDatabases = map dbName (lib.attrNames instances);
          ensureUsers = map (name: {
            name = dbName name;
            ensureDBOwnership = true;
          }) (lib.attrNames instances);
          settings.listen_addresses = lib.mkForce "";
          authentication = lib.mkForce ''
            local all all peer
          '';
        };

        ######## Backups ########

        # Hourly pg_dump of each control-plane database into Garage; dumps older than 30 days are pruned.
        systemd.services.hoard-sync-pg-backup = {
          description = "Dump the Hoard Sync control-plane databases to Garage";
          after = [
            "postgresql.target"
            "garage.service"
          ];
          requires = [ "postgresql.target" ];
          path = [
            config.services.postgresql.package
            pkgs.rclone
          ];
          environment = {
            RCLONE_CONFIG_GARAGE_TYPE = "s3";
            RCLONE_CONFIG_GARAGE_PROVIDER = "Other";
            RCLONE_CONFIG_GARAGE_ENV_AUTH = "true";
            RCLONE_CONFIG_GARAGE_ENDPOINT = garageS3;
            RCLONE_CONFIG_GARAGE_REGION = garageRegion;
          };
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            EnvironmentFile = secretPath "hoard-sync-backup-env";
            PrivateTmp = true;
          };
          script = ''
            set -euo pipefail
            stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
            for db in ${lib.concatMapStringsSep " " dbName (lib.attrNames instances)}; do
              pg_dump --format=custom "$db" | rclone rcat "garage:${pgBackupBucket}/$db/$stamp.dump"
            done
            rclone delete --min-age 30d "garage:${pgBackupBucket}"
          '';
        };
        systemd.timers.hoard-sync-pg-backup = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            RandomizedDelaySec = "5min";
            Persistent = true;
          };
        };

        # Litestream 0.5 in directory mode: every realms/<uuid>/hoard.sqlite, including ones created
        # later, is replicated continuously to hoard-<instance>-litestream under realms/<uuid>/.
        # This is the backup and the migration path (ops/hoard-sync-migration.md in the private hoardapp repo).
        services.litestream = {
          enable = true;
          package = pkgsUnstable.litestream;
          environmentFile = secretPath "hoard-sync-backup-env";
          settings.dbs = lib.mapAttrsToList (name: _: {
            dir = "${stateDir name}/realms";
            pattern = "hoard.sqlite";
            recursive = true;
            watch = true;
            replica = {
              type = "s3";
              bucket = "hoard-${name}-litestream";
              path = "realms";
              endpoint = garageS3;
              region = garageRegion;
              force-path-style = true;
            };
          }) instances;
        };
        # Litestream writes next to the databases (WAL checkpoints, its own metadata), so it joins
        # each instance's group; the servers run with UMask 0007.
        users.users.litestream.extraGroups = map dbName (lib.attrNames instances);
        systemd.services.litestream = {
          after = [
            "garage.service"
            "systemd-tmpfiles-setup.service"
          ];
          wants = [ "garage.service" ];
          serviceConfig.RestartSec = 5;
        };

        # `garage` (a wrapper that loads the admin token) and `litestream` come from their modules.
        environment.systemPackages = [
          pkgs.rclone
          pkgs.sqlite
        ];
      }

      ######## TLS terminates on another host: open the instance ports to that proxy only ########
      (lib.mkIf (cfg.tls == "external") {
        assertions = [
          {
            assertion = cfg.trustedProxy != "127.0.0.1";
            message = "custom.hoardSync.trustedProxy must be the ingress IP when tls = \"external\".";
          }
        ];

        networking.firewall = lib.mkMerge [
          (lib.mkIf (!config.networking.nftables.enable) {
            extraCommands = lib.concatMapStrings (instance: ''
              iptables -A nixos-fw -p tcp -s ${cfg.trustedProxy} --dport ${toString instance.port} -j nixos-fw-accept
            '') (lib.attrValues instances);
          })
          (lib.mkIf config.networking.nftables.enable {
            extraInputRules = lib.concatMapStrings (instance: ''
              ip saddr ${cfg.trustedProxy} tcp dport ${toString instance.port} accept
            '') (lib.attrValues instances);
          })
        ];
      })

      ######## Standalone host: own certificate and Traefik ########
      (lib.mkIf (cfg.tls == "builtin") {
        age.secrets.hoard-sync-cloudflare-env = secret "hoard-sync-cloudflare-env";

        security.acme = {
          acceptTerms = true;
          defaults.email = cfg.acmeEmail;
          certs."hoardapp.dev" = {
            domain = "hoardapp.dev";
            extraDomainNames = [ "*.hoardapp.dev" ];
            dnsProvider = "cloudflare";
            dnsPropagationCheck = true;
            dnsResolver = "1.1.1.1:53";
            credentialsFile = secretPath "hoard-sync-cloudflare-env";
            reloadServices = [ "traefik" ];
          };
        };

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
              websecure.address = ":443";
            };
          };
          dynamicConfigOptions = {
            tls.certificates = [
              {
                certFile = "/var/lib/acme/hoardapp.dev/cert.pem";
                keyFile = "/var/lib/acme/hoardapp.dev/key.pem";
              }
            ];
            http.routers = lib.mapAttrs' (
              name: instance:
              lib.nameValuePair "hoard-sync-${name}" {
                rule = "Host(`${instance.domain}`)";
                entryPoints = [ "websecure" ];
                service = "hoard-sync-${name}";
                tls = { };
              }
            ) instances;
            http.services = lib.mapAttrs' (
              name: instance:
              lib.nameValuePair "hoard-sync-${name}" {
                loadBalancer.servers = [ { url = "http://127.0.0.1:${toString instance.port}"; } ];
              }
            ) instances;
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];
      })
    ]
  );
}
