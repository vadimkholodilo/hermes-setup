# hermes-setup

Run [Hermes Agent](https://hermes-agent.nousresearch.com/) on your own VPS with one command.

- **Docker Compose** runs Hermes (gateway + web dashboard) behind **Traefik**, which handles HTTPS automatically.
- **Ansible** turns a blank Debian/Ubuntu server into a hardened Docker host and deploys the stack.

```
Internet ─▶ :443 Traefik ──(HTTPS)──▶ Hermes dashboard :9119  (Hermes login)
                                      Hermes gateway ─▶ model provider / Telegram / ...
                                      /opt/hermes/data  (all state)
```

Hermes publishes no ports of its own. Traefik is the only way in.
Why Traefik and not nginx: see [docs/reverse-proxy.md](docs/reverse-proxy.md).

**Contents**

1. [Try it locally](#1-try-it-locally)
2. [Deploy to a VPS](#2-deploy-to-a-vps)
3. [After the first deploy](#3-after-the-first-deploy)
4. [Day-to-day operations](#4-day-to-day-operations)
5. [Reference](#5-reference)

---

## 1. Try it locally

You need Docker (Docker Desktop on macOS). Then:

```bash
make dev
```

| Open | What | Login |
|---|---|---|
| http://hermes.localhost:8080 | Hermes dashboard | `dev` / `dev-password` |
| http://localhost:8081 | Traefik UI (dev only) | none |

The Hermes URL also works as a Remote gateway in the Hermes Desktop app.

Useful commands:

| Command | Does |
|---|---|
| `make dev` | Start the stack |
| `make dev-down` | Stop it (your data is kept) |
| `make dev-logs` | Follow the logs |
| `make dev-ps` | Show the containers |
| `make dev-pull` | Pull newer images (then `make dev` again) |
| `make dev-shell` | Open a shell in the Hermes container |
| `make dev-config` | Print the combined dev config |

Good to know:

- The first image pull is about 1.1 GB.
- State lives in `docker/.dev-data/` (gitignored). Delete it to start from scratch.
- The dev stack works like production, but over plain HTTP on localhost: no domain, no certificates, nothing reachable from outside your machine.

---

## 2. Deploy to a VPS

### What you need

- **A VPS:** Ubuntu 24.04 or Debian 12/13, x86_64 or arm64, **at least 2 GB RAM** (4 GB if you'll use browser tools).
- **SSH access with a key**, as `root` or as a user with passwordless sudo (e.g. `ubuntu` on some clouds). Most providers let you add your key when you create the server. No separate admin user is created, because the server only runs Hermes.
- **A domain** with a DNS **A record** (and AAAA if you have IPv6) pointing at the VPS. Set it up **before** deploying, so Let's Encrypt can issue the certificate.
- **On your machine:** `ansible-core` 2.16 or newer (`brew install ansible`).

### Run it

```bash
./deploy.sh        # or: make deploy
```

On the first run it asks for:

- VPS address: an IP, or a `Host` alias from your `~/.ssh/config`
- SSH user: `root` (default), or a user with passwordless sudo
- SSH private key: leave blank to use your default keys, ssh-agent or `~/.ssh/config`; or give a path such as `~/.ssh/my_vps`
- domain
- Let's Encrypt email
- admin username
- whether to use staging certificates

> **Tip:** answer **y** to staging certificates on your first try. This avoids Let's Encrypt rate limits; the browser will show a warning, which is expected. See [Switch to real certificates](#switch-to-real-certificates) when it works.

Then the script:

1. Generates a random admin password and a session secret.
2. Saves all settings to `ansible/inventory/hosts.yml` (gitignored, mode 600).
3. Checks that it can SSH in with your user and key (and, for a non-root user, that `sudo` works without a password).
4. Runs the full Ansible playbook.
5. Prints your login and saves it to `credentials.txt` (gitignored, mode 600).

### Running it again

Re-running `./deploy.sh` reuses the saved settings, so your password stays the same. Use it to upgrade or to re-apply config.

---

## 3. After the first deploy

1. **Sign in.** Open `https://<your-domain>` and use the login from `credentials.txt`.
2. **Set up your model provider** in the dashboard. Or use the CLI wizard on the server:
   ```bash
   ssh <user>@<vps>
   cd /opt/hermes && docker compose exec hermes hermes model     # or: hermes setup
   ```
   The repo never manages the provider. Hermes stores it in `/opt/hermes/data/.env`, and the playbook doesn't touch that file.
3. **Connect Hermes Desktop (optional).** In the app, go to Settings → Gateways → Remote gateway. Enter `https://<your-domain>` and sign in with the same login.

### Switch to real certificates

If you started with staging certificates:

1. Set `acme_staging: false` in `ansible/inventory/hosts.yml`.
2. Delete `/opt/hermes/letsencrypt/acme.json` on the server.
3. Run `make hermes`.

---

## 4. Day-to-day operations

### From your laptop

| Command | Does |
|---|---|
| `make deploy` | Full re-deploy: system config and the Hermes stack |
| `make hermes` | Only redeploy or upgrade the Hermes stack |
| `make check` | Dry run: shows what would change, changes nothing |

### On the server

```bash
ssh <user>@<vps>
cd /opt/hermes
docker compose ps                               # status
docker compose logs -f hermes                   # logs
docker compose exec hermes hermes --help        # Hermes CLI
docker compose pull && docker compose up -d     # upgrade
```

### Common tasks

- **Change the password:** edit `hermes_dashboard_password` in `ansible/inventory/hosts.yml`, then run `make hermes`.
- **Pin a Hermes version:** set `hermes_version` to an exact tag (e.g. `v0.23.4`) in `ansible/group_vars/all/main.yml`. The default is `stable`.
- **Back up:** everything that matters is in `/opt/hermes/data`. It contains credentials, so keep backups private.
  ```bash
  sudo tar czf hermes-$(date +%F).tgz -C /opt/hermes data
  ```
- **Never** run a second `gateway run` container against the same data directory.

---

## 5. Reference

### What the playbook sets up

| Step | What it does |
|---|---|
| `base` role | Full upgrade, base packages, timezone, unattended security upgrades, a 2 GB swap file (added on top of any swap the provider set up). |
| `security` role | SSH: key-only login (passwords disabled), only your SSH user allowed (root can't log in directly unless it *is* that user). Firewall (UFW) opens only ports 22, 80 and 443. fail2ban bans an IP for 20 minutes after 10 failed SSH logins. |
| [`geerlingguy.docker`](https://galaxy.ansible.com/ui/standalone/roles/geerlingguy/docker/) | Docker CE and the compose plugin from Docker's own repo. Log rotation and `live-restore` are set via `docker_daemon_options` in `group_vars`. Pinned in `ansible/requirements.yml`. |
| `hermes` role | Creates `/opt/hermes` with the compose file, `.env` and data directory. Starts the stack, makes Hermes trust Traefik's client IPs, and checks that HTTPS works. |

### Security notes

- **SSH:** only your SSH user, with keys only. Password logins are disabled for everyone. Before changing SSH, the playbook checks that this user has an authorized key, so it can't lock you out. The exact login is in `credentials.txt`.
- **fail2ban:** 10 failed SSH logins within 10 minutes bans that IP for 20 minutes. It runs in `aggressive` mode, because with passwords off, bots never produce "Failed password" lines that normal mode would count. Tune `fail2ban_*` in `ansible/group_vars/all/main.yml`.
- **Firewall:** only ports 22, 80 and 443 are open.

- **Hermes' own login is the only gate.** There's no extra Traefik password, because the Hermes Desktop app can't get past one.
- **Rate limit:** Hermes allows 10 wrong passwords per minute **per client IP**. The playbook sets `dashboard.trusted_proxies` to Traefik's IP so Hermes sees each visitor's real IP. Without it, everyone would share one limit, and a single bot could lock everyone out.
- **Later:** for per-person accounts and 2FA, Hermes supports an OIDC provider such as Keycloak (`HERMES_DASHBOARD_OIDC_ISSUER` / `HERMES_DASHBOARD_OIDC_CLIENT_ID`).

### How the compose files fit together

- `docker/compose.yml` is the production stack and the single source of truth. Ansible copies it to the server as-is.
- The local dev stack is that same file plus:
  - `docker/compose.dev.yml`: overrides (plain HTTP, localhost ports, local data folder)
  - `docker/dev.env`: dev values
- `make dev` combines them for you. It requires Docker Compose 2.24 or newer.

### Repo layout

```
deploy.sh                    one-command deploy; generates password, writes credentials.txt
Makefile                     shortcuts (run `make` to list them)
docker/compose.yml           production stack (single source; Ansible copies it)
docker/.env.example          compose variables (Ansible generates the real .env)
docker/compose.dev.yml       local dev overrides on top of compose.yml
docker/dev.env               dev compose variables (committed, dev-only values)
ansible/site.yml             machine config + deploy (safe to re-run)
ansible/group_vars/all/      defaults (main.yml)
ansible/inventory/hosts.yml  your settings + secrets (created by deploy.sh, gitignored)
ansible/roles/               base, security, hermes (our own roles)
ansible/requirements.yml     Galaxy collections + roles (installed by deploy.sh / `make deps`)
docs/reverse-proxy.md        Traefik vs nginx, adding more apps, exposing the API
```
