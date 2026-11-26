# Reverse proxy: why Traefik (not nginx)

Both are fine. For **this** stack, a single VPS running everything in Docker Compose, Traefik is the better fit.

| | Traefik | nginx |
|---|---|---|
| TLS certs | Built-in Let's Encrypt; issues and renews automatically | Needs certbot (or acme.sh) plus a renewal timer and a reload hook |
| Routing config | Docker labels next to the service in `compose.yml` | Separate vhost files that you keep in sync with containers |
| Adding a service later | Add 4–5 labels | Write a vhost, reload nginx, issue a cert |
| Container IP changes | Discovered through the Docker socket | Static `proxy_pass` targets; containers need fixed names or IPs |
| WebSockets / SSE (the dashboard uses them) | Work out of the box | Need `Upgrade`/`Connection` headers and buffering tweaks |
| Raw performance, static files, fine-grained tuning | Good enough | Better |
| Learning curve | Concepts (routers, middlewares, services) take an hour | Familiar, with lots of examples |

The one trade-off: Traefik mounts `/var/run/docker.sock` (read-only), which gives it insight into your containers. That's normal for a single-tenant box. If that ever bothers you, put a [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) in between.

## How it's wired here

- Traefik is the only container with published ports (80 → redirect, 443).
- Hermes has **no published ports**. Traefik reaches it on the internal `hermes_proxy` network at port 9119 (dashboard) and 9120 (Webapp).
- The Webapp (browser version of Hermes Desktop) is at `/webapp/`. Its router strips the prefix, and Traefik then sends `X-Forwarded-Prefix: /webapp`, which Hermes uses to rewrite its redirects, cookie paths and asset URLs. Requests to a bare `/webapp` are redirected to `/webapp/`, because the page loads its assets from relative `./assets/` paths. It's served by the gateway's own listener, which the playbook turns on with `webapp.enabled/host/port/public_url` in `config.yaml`. `public_url` must match the browser URL, or Hermes rejects the page's writes. Same login and the same per-IP rate limit (`trusted_proxies` covers both listeners, verified locally).
- Traefik only terminates TLS and forwards traffic. There is **no login at the proxy**, so browsers and the Hermes Desktop app talk to Hermes' own login directly.
- **Hermes' dashboard login** (`HERMES_DASHBOARD_BASIC_AUTH_*`) is the gate. Hermes refuses to start the dashboard on `0.0.0.0` without an auth provider. It rate-limits logins to 10 failures per minute per client IP.
- Traefik has a fixed IP (`172.30.0.254`), and the playbook sets `dashboard.trusted_proxies` to it. Hermes then uses the real client IP from `X-Forwarded-For` for that rate limit. Without it, all visitors share Traefik's IP, and one bot could lock everyone out (verified locally).
- Upgrade path: an OIDC provider such as Keycloak (`HERMES_DASHBOARD_OIDC_ISSUER`, `HERMES_DASHBOARD_OIDC_CLIENT_ID`) gives per-person accounts and 2FA. If you ever want a gate at the proxy instead, use Traefik's `forwardAuth` middleware rather than basic auth, because basic auth breaks the desktop app.

## Adding another app later

Put it on the `hermes_proxy` network and add labels:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.myapp.rule=Host(`myapp.example.com`)
  - traefik.http.routers.myapp.entrypoints=websecure
  - traefik.http.routers.myapp.tls.certresolver=letsencrypt
  - traefik.http.services.myapp.loadbalancer.server.port=8080
```

## Exposing the OpenAI-compatible API (optional, not enabled)

The gateway can serve an OpenAI-compatible API on port 8642 (`API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`, `API_SERVER_KEY=...` in `data/.env`). To publish it, add a second router (e.g. `api.` subdomain → port 8642). API clients authenticate with the bearer key.
