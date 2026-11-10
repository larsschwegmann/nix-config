# kamino-revo: Revo time tracking

`time.0x4c53.net` → Traefik on kamino-http-ingress → `192.168.36.211:3000` (Next.js, which proxies
`/api/*` to the FastAPI server on 127.0.0.1:8000). Local PostgreSQL, nightly `pg_dump` to
`/var/backup/revo` (14 days). The service is `services.revo-timetracking` from the private
`larsschwegmann/revo-timetracking` flake (its `DESIGN.md` lists the module options).

## First-time setup

Order matters: CI's nightly `nix flake update` fetches the revo input, so `REVO_DEPLOY_KEY` must
exist before this branch reaches `main`.

1. **LXC.** On the Proxmox host (root@192.168.36.254), as created on 2026-11-09:

   ```bash
   pct create 214 local:vztmpl/nixos-image-lxc-proxmox-25.05pre-git-x86_64-linux.tar.xz \
     --hostname kamino-revo --ostype nixos --unprivileged 0 --features nesting=1 \
     --cores 2 --memory 4096 --swap 2048 --rootfs local-zfs:24 \
     --net0 name=eth0,bridge=vmbr0,ip=192.168.36.211/24,gw=192.168.36.1,type=veth \
     --onboot 1 --ssh-public-keys <your key>.pub --cmode console
   pct start 214
   ```

2. **Host key → secrets.nix.**

   ```bash
   ssh-keyscan -t ed25519 192.168.36.211
   ```

   Add it as `kamino-revo = "ssh-ed25519 … root@kamino-revo";` in `secrets/secrets.nix` and
   uncomment the `"revo-deploy-key.age"` line.

3. **Deploy key.** The comment must be the repo URL (CI routes the key by it).

   ```bash
   ssh-keygen -t ed25519 -N "" -C "git@github.com:larsschwegmann/revo-timetracking.git" -f /tmp/revo-deploy-key
   gh repo deploy-key add /tmp/revo-deploy-key.pub -R larsschwegmann/revo-timetracking -t "kamino-revo + nix-config CI"
   scripts/encrypt-secret.sh revo-deploy-key < /tmp/revo-deploy-key
   gh secret set REVO_DEPLOY_KEY -R larsschwegmann/nix-config < /tmp/revo-deploy-key
   rm /tmp/revo-deploy-key /tmp/revo-deploy-key.pub
   ```

   With `secrets/revo-deploy-key.age` present, the host config turns the key on by itself (the
   evaluation warning about it disappears).

4. **Merge and push** this branch to `main`.

5. **First switch.** The deploy key is only decrypted by agenix after the first switch, and the
   NixOS LXC template has no git. Let the host decrypt the key with its own host key for this one
   run (what agenix does later anyway), then delete it:

   ```bash
   scp secrets/revo-deploy-key.age root@192.168.36.211:
   ssh root@192.168.36.211
   export NIX_CONFIG="experimental-features = nix-command flakes"
   nix run nixpkgs#age -- -d -i /etc/ssh/ssh_host_ed25519_key -o ~/revo-deploy-key ~/revo-deploy-key.age
   chmod 600 ~/revo-deploy-key && rm ~/revo-deploy-key.age   # age writes 0644, ssh refuses that
   printf 'Host github.com\n  IdentityFile /root/revo-deploy-key\n  IdentitiesOnly yes\n' > ~/.ssh/config
   echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" >> ~/.ssh/known_hosts
   nix shell nixpkgs#git nixpkgs#openssh nixpkgs#nixos-rebuild \
     -c nixos-rebuild switch --flake github:larsschwegmann/nix-config#kamino-revo
   rm ~/revo-deploy-key ~/.ssh/config
   runuser -u revo -- revo set-password lars
   ```

   The build takes about 5 minutes and peaks at ~2.4 GB RAM (the LXC has 4 GB + 2 GB swap). From
   then on `autoUpgrade` fetches with `/run/agenix/revo-deploy-key`.

6. **Ingress.** kamino-http-ingress picks up the route on its next auto-upgrade (04:00), or now:
   `nixos-rebuild switch --flake github:larsschwegmann/nix-config#kamino-http-ingress` on that host.
   The ACME wildcard `*.0x4c53.net` already covers `time.0x4c53.net`. From outside it needs its own
   Cloudflare record (there is no wildcard): A `91.107.225.201` (cloudgw), DNS only, like jellyfin.

7. **Check.** `https://time.0x4c53.net` on the LAN and from outside. In the web app, Settings → API
   tokens → create one for the menubar app, and set the app's server URL to `https://time.0x4c53.net`.

## Operations

- Logs: `journalctl -u revo-api -u revo-web`. Migrations run before every API start (`revo-migrate`).
- Backups: `ls /var/backup/revo`; restore with `runuser -u revo -- pg_restore --clean -d revo <file>`.
  They stay on this LXC: include it in the Proxmox backups if you want an off-host copy.
- Updating revo: push to revo-timetracking's `main`; the nightly lock update and auto-upgrade deploy it.
  To deploy right away: update the `revo` entry in `flake.lock` (`nix flake update revo`), push, then on the host
  `nixos-rebuild switch --refresh --flake github:larsschwegmann/nix-config#kamino-revo`. Without `--refresh`, Nix
  reuses its cached `github:` ref for up to an hour and quietly rebuilds the previous commit.
