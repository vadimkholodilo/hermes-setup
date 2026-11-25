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
- Locally: `ansible-core` ≥ 2.16 (`brew install ansible`) and an SSH key
- Your SSH key authorized for the VPS's initial user (usually `root`). Most providers let you add it when you create the server.

## Deploy

```bash
./deploy.sh
```

On the first run the script asks for the VPS IP, initial SSH user, domain, Let's Encrypt email, admin username and SSH key. Then it:

1. **Generates** a random 24-character admin password and a session secret.
2. **Saves the settings** to `ansible/inventory/hosts.yml` (gitignored, chmod 600).
3. **Bootstraps the server** (creates the `deploy` user), unless that user can already log in.
4. **Runs the full playbook.**
5. **Prints the login** and saves it to `credentials.txt` next to the script (gitignored, chmod 600).

Re-running `./deploy.sh` reuses the saved settings, so the password stays the same. Use it to upgrade or re-apply config. `./deploy.sh --tags hermes` (or `make hermes`) only redeploys the stack. To change the password, edit `hermes_dashboard_password` in `ansible/inventory/hosts.yml` and re-run.

Tip: answer "y" to the staging-certs question for the first test, to avoid Let's Encrypt rate limits. Afterwards, set `acme_staging: false` in `hosts.yml`, delete `/opt/hermes/letsencrypt/acme.json` on the server, and run `make hermes`.

## After first deploy

1. Open `https://<your-domain>` and sign in with the username and password from `credentials.txt`.
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
deploy.sh                    one-command deploy; generates password, writes credentials.txt
ansible/group_vars/all/      defaults (main.yml); your settings + secrets go in inventory/hosts.yml
ansible/roles/               base, security, docker, hermes
docs/reverse-proxy.md        Traefik vs nginx, adding more apps, exposing the API
```
