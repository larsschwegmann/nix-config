let
  cloudgw = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAWJuctcVfG5x2nGKs76fEuQOuyDqDAJwiQllW0eFaz root@cloudgw";
  kamino-http-ingress = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA51CR4/jH7W/MCuI0p4zYaW31tqWuvTejpX9f6ECX/8 root@kamino-http-ingress";
  lars = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTxrW9jRI2GrxpnAFUfOgz79+exH4zOQYV+Qw9Ge5MM lars@mandalore";
in {
  "cloudgw-wg-private.age".publicKeys = [ lars cloudgw ];
  "kamino-http-ingress-wg-private.age".publicKeys = [ lars kamino-http-ingress ];
}
