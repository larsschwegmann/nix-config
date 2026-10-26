# Public keys only: who can decrypt which agenix secret. This repo is public; plaintext never
# goes in it. Encrypt with scripts/encrypt-secret.sh (brew age, no nix needed).
let
  cloudgw = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAWJuctcVfG5x2nGKs76fEuQOuyDqDAJwiQllW0eFaz root@cloudgw";
  kamino-http-ingress = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA51CR4/jH7W/MCuI0p4zYaW31tqWuvTejpX9f6ECX/8 root@kamino-http-ingress";
  # TODO(owner): the LXC's host key, from `ssh-keyscan -t ed25519 <its IP>` (ops/hoard-sync-setup.md in the private hoardapp repo).
  # scripts/encrypt-secret.sh refuses to encrypt while this is still a TODO.
  kamino-hoard-sync = "TODO-kamino-hoard-sync-host-key";
  lars = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore";
in {
  "cloudgw-wg-private.age".publicKeys = [ lars cloudgw ];
  "kamino-http-ingress-wg-private.age".publicKeys = [ lars kamino-http-ingress ];
  "kamino-http-ingress-hoardapp-cloudflare-env.age".publicKeys = [ lars kamino-http-ingress ];

  # Hoard Sync (modules/hoard-sync). On a move, add the new host's key here and re-encrypt.
  "hoardapp-deploy-key.age".publicKeys = [ lars kamino-hoard-sync ];
  "hoard-sync-garage-env.age".publicKeys = [ lars kamino-hoard-sync ];
  "hoard-sync-prod-env.age".publicKeys = [ lars kamino-hoard-sync ];
  "hoard-sync-staging-env.age".publicKeys = [ lars kamino-hoard-sync ];
  "hoard-sync-backup-env.age".publicKeys = [ lars kamino-hoard-sync ];
  "hoard-sync-appstore-key.age".publicKeys = [ lars kamino-hoard-sync ];
  # Only for a standalone host with tls = "builtin" (ops/hoard-sync-migration.md in the private hoardapp repo).
  "hoard-sync-cloudflare-env.age".publicKeys = [ lars ];
}
