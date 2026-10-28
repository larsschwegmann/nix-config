# Public keys only: who can decrypt which agenix secret. This repo is public; plaintext never
# goes in it. Encrypt with scripts/encrypt-secret.sh (brew age, no nix needed).
let
  cloudgw = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAWJuctcVfG5x2nGKs76fEuQOuyDqDAJwiQllW0eFaz root@cloudgw";
  kamino-http-ingress = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA51CR4/jH7W/MCuI0p4zYaW31tqWuvTejpX9f6ECX/8 root@kamino-http-ingress";
  kamino-hoard-sync = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKOOI1I9t8Xph4JyolwRA6wfdXesKRQaM8fLss8IHqZL root@kamino-hoard-sync";
  lars = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore";
  # age can't decrypt through 1Password's SSH agent, so the Hoard Sync secrets also go to this age
  # key, kept in 1Password ("Hoard Sync age key"):
  #   age -d -i <(op read "op://Private/Hoard Sync age key/password") secrets/<name>.age
  lars-age = "age1urnz7zca5vg2g689jn8c9uzp4prszqf9g3zrsgpkn8cchujpsgeq74k5wc";
in {
  "cloudgw-wg-private.age".publicKeys = [ lars cloudgw ];
  "kamino-http-ingress-wg-private.age".publicKeys = [ lars kamino-http-ingress ];
  "kamino-http-ingress-hoardapp-cloudflare-env.age".publicKeys = [ lars lars-age kamino-http-ingress ];

  # Hoard Sync (modules/hoard-sync). On a move, add the new host's key here and re-encrypt.
  "hoardapp-deploy-key.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-garage-env.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-prod-env.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-staging-env.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-backup-env.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-appstore-key.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  # S3 Manager (LAN-only bucket browser): a read-only Garage key, and the htpasswd for its login.
  "hoard-sync-s3manager-env.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  "hoard-sync-s3manager-htpasswd.age".publicKeys = [ lars lars-age kamino-hoard-sync ];
  # Only for a standalone host with tls = "builtin" (ops/hoard-sync-migration.md in the private hoardapp repo).
  "hoard-sync-cloudflare-env.age".publicKeys = [ lars lars-age ];
}
