#!/usr/bin/env bash
# Encrypt plaintext from stdin into secrets/<name>.age, for the recipients secrets/secrets.nix lists
# for it. Needs only `brew install age` (agenix files are plain age files; age accepts ssh-ed25519
# recipients). The plaintext never touches the disk unless you put it there.
#
#   scripts/encrypt-secret.sh hoard-sync-prod-env < /dev/stdin
#   pbpaste | scripts/encrypt-secret.sh kamino-http-ingress-hoardapp-cloudflare-env
#   scripts/encrypt-secret.sh hoard-sync-appstore-key < ~/Downloads/AuthKey_XXXXXXXXXX.p8
#
# Re-encrypt for changed recipients (a new host key):
#   age -d -i ~/.ssh/id_ed25519 secrets/<name>.age | scripts/encrypt-secret.sh <name>
set -euo pipefail

die() {
  echo "encrypt-secret: $*" >&2
  exit 1
}

[ $# -eq 1 ] || die "usage: $0 <secret name, e.g. hoard-sync-prod-env>"
name=${1%.age}
name=${name#secrets/}

root=$(cd "$(dirname "$0")/.." && pwd)
secrets_nix=$root/secrets/secrets.nix
command -v age >/dev/null || die "age not found (brew install age)"

line=$(grep -E "^[[:space:]]*\"$name\.age\"\.publicKeys" "$secrets_nix") ||
  die "no \"$name.age\".publicKeys entry in secrets/secrets.nix"
ids=$(printf '%s\n' "$line" | sed -E 's/.*\[(.*)\].*/\1/')

recipients=()
for id in $ids; do
  key=$(sed -nE "s/^[[:space:]]*$id[[:space:]]*=[[:space:]]*\"([^\"]*)\";.*/\1/p" "$secrets_nix")
  [ -n "$key" ] || die "recipient '$id' is not defined in secrets/secrets.nix"
  case $key in
    ssh-ed25519\ * | age1*) ;;
    *) die "recipient '$id' is not a public key yet ($key); fill it in secrets/secrets.nix first" ;;
  esac
  recipients+=(-r "$key")
done
[ ${#recipients[@]} -gt 0 ] || die "no recipients for $name.age"

[ -t 0 ] && echo "Paste the plaintext for $name, then Ctrl-D:" >&2

# Encrypt to a temporary file first, so re-encrypting a secret piped from itself is safe.
out=$root/secrets/$name.age
tmp=$(mktemp "$root/secrets/.$name.XXXXXX")
trap 'rm -f "$tmp"' EXIT
age "${recipients[@]}" -o "$tmp"
[ -s "$tmp" ] || die "age produced no output"
mv "$tmp" "$out"
trap - EXIT
echo "wrote secrets/$name.age for: $ids" >&2
