# hermes-setup

Everything needed to put [Hermes Agent](https://hermes-agent.nousresearch.com/) on a fresh VPS:

- **`docker/compose.yml`**: Hermes (gateway + web dashboard) behind **Traefik** with automatic HTTPS
- **`ansible/`**: turns a blank Debian/Ubuntu VPS into a hardened Docker host and deploys the stack

Why Traefik instead of nginx: see [docs/reverse-proxy.md](docs/reverse-proxy.md).

## Try it locally first

`docker/compose.dev.yml` runs the same image on your machine. It has the same shape as production: Hermes publishes no ports and is only reachable through Traefik. It uses plain HTTP on localhost, with no domain and no certificates.

```bash
cd docker
docker compose -f compose.dev.yml up -d
```

| URL | Login |
|---|---|
| http://hermes.localhost:8080 | Hermes: `dev` / `dev-password` (also works as the Desktop app's Remote gateway URL) |
| http://localhost:8081 | Traefik's own UI (routers/middlewares), dev only |

State lives in `docker/.dev-data/` (gitignored). Stop with `docker compose -f compose.dev.yml down`. Delete `.dev-data/` to start from scratch. The first image pull is about 1.1 GB.

```
Internet ─▶ :443 Traefik ──(TLS)──▶ hermes:9119 dashboard (Hermes login)
                                                 hermes gateway ─▶ model provider / Telegram / ...
                                                 /opt/hermes/data  (all state)
```

## What the playbook does

| Role | |
|---|---|
| `bootstrap.yml` | Run once as root: creates the `deploy` admin user with your SSH key and passwordless sudo |
| `base` | Full upgrade, base packages, timezone, unattended security upgrades, 2 GB swap |
| `security` | SSH: key-only, no root, `AllowUsers deploy`. UFW allows only 22/80/443. fail2ban for sshd |
| `docker` | Docker CE and the compose plugin from Docker's repo, log rotation |
| `hermes` | `/opt/hermes` with compose file, `.env` and data dir; pulls and starts the stack; makes Hermes trust Traefik's forwarded client IPs; checks HTTPS |

The model provider is **not** configured by the playbook. Set it up in the dashboard after the first deploy (it's stored in `/opt/hermes/data/.env`, which the playbook never touches).

## Requirements

- VPS: Ubuntu 24.04 or Debian 12/13, **≥ 2 GB RAM** (4 GB if you'll use browser tools), x86_64 or arm64
- A DNS **A record** (and AAAA if you have IPv6) for your domain pointing at the VPS, set **before** deploying so Let's Encrypt can issue the cert
- Locally: `ansible-core` ≥ 2.16 and an SSH key (`~/.ssh/id_ed25519.pub` by default)

## Deploy

```bash
make deps                                    # install Ansible collections

cd ansible
cp inventory/hosts.example.yml inventory/hosts.yml        # set the VPS IP
cp group_vars/all/vault.example.yml group_vars/all/vault.yml
$EDITOR group_vars/all/main.yml              # hermes_domain, acme_email (and admin_user / ssh key if needed)
$EDITOR group_vars/all/vault.yml             # two secrets: openssl rand -base64 24 / openssl rand -hex 32
ansible-vault encrypt group_vars/all/vault.yml
cd ..

make bootstrap   # once, as root (or: cd ansible && ansible-playbook bootstrap.yml -e bootstrap_user=ubuntu)
ssh deploy@<vps-ip>   # confirm the new user works before continuing
make deploy      # everything else; safe to re-run
```

Tip: for the first test set `acme_staging: true` to avoid Let's Encrypt rate limits. Then set it back to `false`, delete `/opt/hermes/letsencrypt/acme.json`, and run `make hermes`.

## After first deploy

1. Open `https://<your-domain>` and sign in with `hermes_dashboard_username` and the vault password.
2. **Configure your model provider** in the dashboard. Alternatively, use the CLI wizard:
   ```bash
   ssh deploy@<vps>
   cd /opt/hermes && docker compose exec hermes hermes model     # or: hermes setup
   ```
3. **Hermes Desktop** (you or a friend): go to Settings → Gateways → Remote gateway, enter `https://<your-domain>`, then Sign in with the same login.

The playbook already sets `dashboard.trusted_proxies` to Traefik's IP. Hermes allows 10 wrong passwords per minute **per client IP**. Without this setting, every visitor would look like Traefik, and one bot could lock everyone out.

Later, for per-person accounts and 2FA, Hermes supports an OIDC provider such as Keycloak (`HERMES_DASHBOARD_OIDC_ISSUER` / `HERMES_DASHBOARD_OIDC_CLIENT_ID`).

## Day-2 operations

```bash
cd /opt/hermes
docker compose ps
docker compose logs -f hermes
docker compose exec hermes hermes --help        # Hermes CLI inside the container
docker compose pull && docker compose up -d     # upgrade (or: make hermes from your laptop)
```

- **Pin versions:** set `hermes_version` in `group_vars/all/main.yml` to an exact tag once you're happy. The default is `stable`.
- **Backups:** everything that matters is in `/opt/hermes/data`. It contains credentials, so keep backups private. Example:
  `sudo tar czf hermes-$(date +%F).tgz -C /opt/hermes data`
- **Never run a second `gateway run` container** against the same data dir.

## Layout

```
docker/compose.yml           stack definition (single source; Ansible copies it)
docker/.env.example          compose variables (Ansible generates the real one)
ansible/bootstrap.yml        first-run admin user
ansible/site.yml             idempotent machine config + deploy
ansible/group_vars/all/      settings (main.yml) and secrets (vault.yml, gitignored)
ansible/roles/               base, security, docker, hermes
docs/reverse-proxy.md        Traefik vs nginx, adding more apps, exposing the API
```
