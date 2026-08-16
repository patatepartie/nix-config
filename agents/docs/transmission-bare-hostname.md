# Serve Transmission at a bare `transmission.local` (no `:9091`)

**Status:** skeleton only — not designed, not implemented. Written 2026-08-16 to
hand to a dedicated session.
**Affects:** `hosts/home-server/configuration.nix`, and possibly whatever deploys
`kamal-proxy` (which is *not* this repo — see "The awkward part").
**Goal:** reach the Transmission web UI at `http://transmission.local` instead of
`http://transmission.local:9091`.

## Where things stand today

Working now, verified 2026-08-15:

- `transmission.local` resolves over mDNS, published by
  `systemd.services.avahi-publish-transmission` in `configuration.nix`, modelled
  on the existing `avahi-publish-cash22` unit. Both **hardcode `192.168.0.17`**.
- `http://transmission.local:9091` serves the web UI (HTTP 200 from the MacBook).
- The daemon binds `rpc-bind-address = "0.0.0.0"`, port 9091, no authentication,
  `rpc-whitelist = "127.0.0.1,::1,192.168.0.*"`, `rpc-host-whitelist-enabled = false`.

Only the `:9091` is unwanted. Everything else about the setup is settled.

## Why `cash22.local` needs no port

`kamal-proxy` runs in Docker with `0.0.0.0:80->80` and `0.0.0.0:443->443`, and
routes by `Host:` header:

```
$ docker exec kamal-proxy kamal-proxy list
Service     Host          Path  Target           State    TLS
cash22-web  cash22.local  /     10081b9af14d:80  running  no
```

So port 80 is already taken on this host, by a proxy that is doing exactly the
job Transmission needs. That is the opportunity and the complication.

## The awkward part — read this before choosing an approach

**`kamal-proxy` is not managed by this repo.** Only the mDNS name is. The
container is deployed by Kamal from the cash22 project with
`restart: unless-stopped` and `Cmd: ["kamal-proxy","run"]`. Its routing table is
runtime state, added via `kamal-proxy deploy`-style commands, not a file in
`nix-config`.

That means any approach routing Transmission through kamal-proxy has to answer:

- Where does the route definition live so it survives a redeploy of cash22?
- Who re-adds it after the container restarts? (Routes are held by the running
  proxy; `restart: unless-stopped` restarts the container, not necessarily the
  route table.)
- Does adding a non-Kamal service to a Kamal-owned proxy fight the tool's model?

**Verify the persistence question first** — it likely decides the whole design.
If kamal-proxy loses the Transmission route whenever cash22 redeploys, routing
through it is a maintenance trap and a separate proxy is better.

## Approaches to evaluate

Not yet assessed. Roughly in order of how well they fit this repo's conventions.

1. **A second reverse proxy on a different interface/port.** Nginx or Caddy via
   NixOS options (`services.nginx.virtualHosts."transmission.local"`), proxying
   to `127.0.0.1:9091`. Fully declarative and in-repo, but **port 80 is already
   bound by kamal-proxy**, so this needs another address to listen on — e.g. bind
   to a second IP, or publish `transmission.local` as a *different* address that
   the proxy owns. Check whether `avahi-publish -a` can advertise an address the
   host does not already have.
2. **Add a route to the existing kamal-proxy.** Least new infrastructure, reuses
   the working port-80 binding. But see "The awkward part" — persistence and
   ownership are unresolved, and the route would live outside this repo.
3. **Move Transmission's RPC to port 80 directly.** Simplest conceptually,
   impossible in practice: kamal-proxy already holds `0.0.0.0:80`. Only viable if
   Transmission binds a *different* address on port 80. Probably a dead end;
   confirm and discard.
4. **Do nothing; use a bookmark.** The port is a cosmetic annoyance. Worth stating
   as the baseline any other option has to beat, given the maintenance cost of
   options 1 and 2.

## Constraints to respect

- **Never run mutating `brew`/`docker` commands by hand** to make this work — the
  repo's convention is declarative config, applied via `just switch`.
- The mDNS units hardcode `192.168.0.17`. If a new approach needs a second
  address, that hardcoding becomes load-bearing and should probably be fixed at
  the same time.
- Transmission RPC is deliberately **unauthenticated**, restricted by
  `rpc-whitelist` to `192.168.0.*`. Putting it behind a proxy on port 80 changes
  the source address the daemon sees to the proxy's, which **will** interact with
  that whitelist. Check this explicitly — a proxy may make the whitelist either
  useless or accidentally blocking.
- `rpc-host-whitelist-enabled` is currently `false`. If it is ever re-enabled, a
  proxy changing the `Host:` header will produce **HTTP 421**, which looks like a
  broken proxy rather than a whitelist problem.

## Definition of done

- `http://transmission.local` serves the web UI from the MacBook, no port.
- `http://cash22.local` still works, unchanged.
- The change survives a reboot **and** a cash22 redeploy.
- Whatever holds the routing config is either in this repo or documented as
  deliberately outside it.

## Scope

Self-contained. Depends on nothing from the session-decoupling work beyond the
already-working `transmission.local` name and the daemon's RPC settings, both
described above. See `home-server-session-decoupling.md` for how those got there.
