# kamino-revo: Revo time tracking

`time.0x4c53.net` → Traefik on kamino-http-ingress → `192.168.36.211:3000` (Next.js, which proxies
`/api/*` to the FastAPI server on 127.0.0.1:8000). Local PostgreSQL, nightly `pg_dump` to
`/var/backup/revo` (14 days). The service is `services.revo-timetracking` from the private
`larsschwegmann/revo-timetracking` flake (its `DESIGN.md` lists the module options).

## First-time setup

Order matters: CI's nightly `nix flake update` fetches the revo input, so `REVO_DEPLOY_KEY` must
exist before this branch reaches `main`.

1. **LXC.** In Proxmox, create `kamino-revo` like the other kamino hosts (NixOS LXC template,
   privileged), static IP `192.168.36.211`, your SSH key for root.

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

5. **First switch.** The deploy key is only decrypted after the first switch, so fetch the revo
   input with your forwarded agent this once:

   ```bash
   ssh -A root@192.168.36.211
   ssh-keyscan github.com >> ~/.ssh/known_hosts
   nixos-rebuild switch --flake github:larsschwegmann/nix-config#kamino-revo
   runuser -u revo -- revo set-password lars
   ```

   From then on `autoUpgrade` fetches with the deploy key.

6. **Ingress.** kamino-http-ingress picks up the route on its next auto-upgrade (04:00), or now:
   `nixos-rebuild switch --flake github:larsschwegmann/nix-config#kamino-http-ingress` on that host.
   The ACME wildcard `*.0x4c53.net` already covers `time.0x4c53.net`. From outside, it also needs a
   public DNS record (Cloudflare) like the other `0x4c53.net` services, unless a wildcard exists.

7. **Check.** `https://time.0x4c53.net` on the LAN and from outside. In the web app, Settings → API
   tokens → create one for the menubar app, and set the app's server URL to `https://time.0x4c53.net`.

## Operations

- Logs: `journalctl -u revo-api -u revo-web`. Migrations run before every API start (`revo-migrate`).
- Backups: `ls /var/backup/revo`; restore with `runuser -u revo -- pg_restore --clean -d revo <file>`.
  They stay on this LXC: include it in the Proxmox backups if you want an off-host copy.
- Updating revo: push to revo-timetracking's `main`; the nightly lock update and auto-upgrade deploy it.
