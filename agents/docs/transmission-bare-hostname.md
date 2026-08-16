# Serve Transmission at a bare `transmission.local` (no `:9091`)

**Status:** done, verified 2026-08-16 including across a reboot.
**Affects:** `hosts/home-server/configuration.nix`.
**Result:** `http://transmission.local` serves the Transmission web UI.

## What was built

`kamal-proxy` already held `0.0.0.0:80` and routes by `Host:` header, so the
Transmission UI was registered with it as a second service rather than by
standing up a competing proxy. Two changes, both in `configuration.nix`:

1. `systemd.services.kamal-proxy-route-transmission` — a `oneshot` unit that
   runs `kamal-proxy deploy transmission --target 172.18.0.1:9091 --host
   transmission.local --health-check-path /transmission/web/`.
2. `rpc-whitelist` gained `172.18.0.*`.

That second one is the non-obvious part. Proxied requests reach the daemon from
**kamal-proxy's container address (`172.18.0.2`)**, not the client's, so the
previous `192.168.0.*` would have answered 403 to every proxied request. If this
ever starts 403ing, check the whitelist before suspecting the proxy.

The target is `172.18.0.1:9091` — the `kamal` bridge **gateway**, i.e. the host
as seen from inside the container. Not `127.0.0.1`, which inside the container is
the proxy itself.

## The two questions the skeleton left open, answered

**Does a hand-added route survive a cash22 redeploy? Yes.** kamal-proxy persists
its routing table to `kamal-proxy.state` in the **named Docker volume**
`kamal-proxy-config` (mounted at `~/.config/kamal-proxy`), not in memory. The
state is a JSON array whose entries are **keyed by service name**:

```json
[{"name":"cash22-web","options":{"hosts":["cash22.local"],...}},
 {"name":"transmission","options":{"hosts":["transmission.local"],...}}]
```

`kamal deploy` from cash22 rewrites only the `cash22-web` entry. Combined with
`restart: unless-stopped`, the route survives container restarts and reboots.
This is what made option 2 viable and killed the skeleton's main worry.

**Can kamal-proxy route to services Kamal does not deploy? Yes.** `kamal-proxy
deploy` takes an arbitrary `--target host:port`; nothing requires the target to
be a Kamal-managed container. Transmission is a plain host service and works fine.

Because persistence was not in fact a problem, **option 1 (a second proxy on a
second IP) was never needed** — which is a relief, since it would have meant
moving interface configuration out of NetworkManager and into nix, a much larger
and riskier change than this feature justifies.

## Why the unit exists at all, given the state persists

The route would survive without it. The unit is there so the **declaration lives
in this repo** rather than only as runtime state in a Docker volume, and so the
route self-heals if that volume is ever recreated. `kamal-proxy deploy` is
idempotent, so re-asserting on every boot is free.

It carries `startLimitIntervalSec = 600` / `startLimitBurst = 40` because
kamal-proxy is a container Kamal starts on its own schedule and may not be up yet
on a cold boot. systemd's default of 5 attempts would be too few; this retries
for ~10 minutes.

## Verification

Run from the MacBook. All confirmed passing 2026-08-16, immediately after
`just switch`:

```sh
curl -s -L -o /dev/null -w '%{http_code}\n' http://transmission.local/   # 200
curl -s -o /dev/null -w '%{http_code}\n' http://cash22.local/            # 200, unchanged
curl -s -o /dev/null -w '%{http_code}\n' http://transmission.local/transmission/rpc  # 409
ssh home-server.local docker exec kamal-proxy kamal-proxy list           # both services listed
ssh home-server.local systemctl is-active kamal-proxy-route-transmission transmission display-manager
```

Two response codes that look like failures and are not:

- **`http://transmission.local/` returns 301**, not 200. That is Transmission's
  own redirect to `/transmission/web/`; it does the same on `:9091`, so it is
  pre-existing and not proxy-induced. Use `curl -L` — browsers follow it silently.
  The definition of done said "200"; 301-then-200 is the correct shape.
- **`/transmission/rpc` returns 409.** That is the healthy handshake asking for a
  session id. `421` would mean a host-whitelist rejection, `403` an IP-whitelist
  one — the latter is the failure mode to expect if the `172.18.0.*` entry is
  ever lost.

The health check passed on the first deploy (`NRestarts=0`, `Result=success`),
so the `--force` fallback was not needed.

## Reboot behaviour

Tested on a real cold boot 2026-08-16: both hostnames served correctly, the unit
reported `Result=success` with `NRestarts=0`, and `systemctl --failed` was empty.

Zero restarts means kamal-proxy's container happened to be up before the unit
ran. Do not read that as proof the ordering is guaranteed — `wants`/`after` on
`docker.service` waits for the daemon, not for Kamal's container, so a slower
boot could still find the proxy missing. That is what the retry window is for. If
this ever looks broken after a reboot, check `NRestarts` and
`systemctl status kamal-proxy-route-transmission` before concluding the design is
wrong; a few restarts followed by success is the system working as intended.

## Outstanding

- The `avahi-publish-*` units still hardcode `192.168.0.17`. Untouched by this
  work and still a latent wart, but no longer load-bearing for anything here,
  since no second address was needed.

## Scope

Self-contained. `kamal-proxy` itself remains deployed by Kamal from
`~/Tech/Perso/cash22` and is not managed by this repo; the cash22 `deploy.yml`
was **not** modified. See `home-server-session-decoupling.md` for how
`transmission.local` and the daemon's RPC settings got there.
