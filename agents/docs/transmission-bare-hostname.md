# Serve Transmission at a bare `transmission.local` (no `:9091`)

**Status:** skeleton only — not designed, not implemented. Written 2026-08-16 to
hand to a dedicated session.
**Affects:** `hosts/home-server/configuration.nix`, and possibly whatever deploys
`kamal-proxy` (which is *not* this repo — see "The awkward part").
**Goal:** reach the Transmission web UI at `http://transmission.local` instead of
`http://transmission.local:9091`.

## Orientation — read this first if you have no context

The host is **home-server** (NixOS, `hosts/home-server/` in this flake), reachable
as `home-server.local` at `192.168.0.17`. It is an always-on box running Samba,
Docker, MQTT and Transmission, with a GNOME desktop the user stays logged into.

Two things about working on it that are not obvious and will cost you time:

- **SSH must be plain and unquoted-ish.** `ssh home-server.local <cmd>` is
  sandbox-excluded, so mDNS resolves. Adding *any* flag between `ssh` and the
  hostname (`ssh -o ... home-server.local`) breaks the exclusion, the command runs
  inside the sandbox, and you get `Could not resolve hostname home-server.local`
  — which is a sandbox artifact, **not** the host being down. `scp` is likewise
  not excluded; pipe through `ssh` instead. See the repo's
  `agents/instructions/working-in-this-repo.md`.
- **You cannot `sudo` over SSH.** `just switch` needs it, so hand that command to
  the user to run. Everything up to and including `nix build` you can do yourself.

**Deploying without pushing.** The auto-update job hard-resets to `origin/main`,
but there is a checkout at **`/home/patate/tech/nix-config`** on the server. Push
to `origin/main` and `git pull --ff-only` there, or transfer an unpushed commit
with `git format-patch -1 HEAD --stdout | ssh home-server.local "cat > /tmp/x.patch"`
then `git am`. Build with `nix build --no-link --print-out-paths
'.#nixosConfigurations.home-server.config.system.build.toplevel'` to catch errors
before asking the user to switch.

**Evaluation is not verification.** Every real defect in the work that produced
this setup passed `nix eval` and `nix build` cleanly and only failed when run on
the machine — a systemd `226/NAMESPACE` mount failure, an HTTP 421, a config path
that did not exist. Budget for testing on the box.

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
`restart: unless-stopped` and `Cmd: ["kamal-proxy","run"]`.

The cash22 route is declared in **`~/Tech/Perso/cash22/config/deploy.yml`**:

```yaml
service: cash22
proxy:
  ssl: false
  host: cash22.local
```

So the routing is *not* purely ephemeral — Kamal re-asserts that route from this
file on every deploy. But it is a **one-service-per-deploy-file** model: that
`proxy:` block describes the cash22 app, not a general routing table. A
Transmission route added by hand to the running proxy is runtime-only state and
would be at the mercy of the next `kamal deploy`.

Questions this leaves open, in the order worth answering:

- Does a manually-added `kamal-proxy` route survive a cash22 redeploy? Test it
  rather than reasoning about it — the answer decides between options 1 and 2.
- Does `kamal-proxy` support routes for services Kamal does not deploy, and is
  there a supported way to declare one? (Check kamal-proxy's own docs; Transmission
  is a plain container-less host service, which is not Kamal's usual target.)
- If the route must live in `deploy.yml`, that puts nix-config's networking
  config inside an unrelated app's deploy file. Is the user happy with that split?
  **Ask before editing the cash22 repo.**

**Verify the persistence question first** — it likely decides the whole design.
If kamal-proxy loses the Transmission route whenever cash22 redeploys, routing
through it is a maintenance trap and a separate proxy is better.

### Re-deriving these facts

All of the above came from these commands; re-run them rather than trusting the
values, which will drift:

```sh
ssh home-server.local docker ps --format '{{.Names}}\t{{.Ports}}'
ssh home-server.local docker exec kamal-proxy kamal-proxy list
ssh home-server.local "docker inspect kamal-proxy --format '{{json .HostConfig.RestartPolicy}} {{json .Config.Cmd}}'"
ssh home-server.local "ss -tlnp | grep -E ':80|:443|:9091'"
```

The cash22 project lives at **`~/Tech/Perso/cash22`** on the user's MacBook (it is
a gascity rig; see the repo's `working-in-this-repo.md` for what that means). If
the answer involves changing how kamal-proxy is deployed, the change belongs in
*that* repo, not this one — check with the user before editing it.

## Approaches to evaluate

Not yet assessed. Roughly in order of how well they fit this repo's conventions —
but note that ordering is about *fit*, not feasibility. The two front-runners each
have an unresolved blocker (kamal-proxy binds `0.0.0.0:80`, so a second IP does
not by itself free port 80; and a hand-added kamal route may not survive a
redeploy). **Resolve those two questions before writing any config** — between
them they eliminate at least one option.

1. **A second reverse proxy on a second IP.** Nginx or Caddy via NixOS options
   (`services.nginx.virtualHosts."transmission.local"`), proxying to
   `127.0.0.1:9091`. Fully declarative and entirely in this repo, which fits the
   conventions best. The obstacle is that **port 80 is already bound by
   kamal-proxy on `0.0.0.0`**, so a second listener needs its own address.

   Groundwork already done:
   - The box has **one** LAN interface, `enp1s0`, with a single address
     `192.168.0.17/24` (`noprefixroute`). `docker0` and `br-9b525925c75a` are
     Docker bridges.
   - That address is **not** set in this repo — `networking.networkmanager.enable
     = true` and nothing declares the interface, so it comes from NetworkManager
     (router reservation or a NM connection profile). Confirm with
     `ssh home-server.local nmcli -g ipv4.method,ipv4.addresses connection show <name>`.
   - So adding an IP alias means either a NetworkManager profile change or moving
     interface config into nix. Decide deliberately: taking over the interface
     declaratively is a bigger change than this feature warrants, and getting it
     wrong makes the box unreachable.
   - Then `avahi-publish -a -R transmission.local <new-ip>` instead of
     `192.168.0.17`, mirroring the existing unit.

   Note kamal-proxy binds `0.0.0.0:80`, which **includes any new address on the
   host**. Adding an IP alias alone will not free port 80 on it — check whether
   kamal-proxy can be pinned to `192.168.0.17:80` instead, or accept that a second
   proxy needs a different port after all (which defeats the purpose).
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

### How to test

```sh
# From the MacBook. 200 = the web UI is being served.
curl -s -o /dev/null -w '%{http_code}\n' http://transmission.local/
curl -s -o /dev/null -w '%{http_code}\n' http://cash22.local/          # must still be 200

# The RPC endpoint behind it. 409 is CORRECT — it is the handshake asking for a
# session id. 421 means a host-whitelist rejection, 403 an IP-whitelist one.
curl -s -o /dev/null -w '%{http_code}\n' http://transmission.local/transmission/rpc

# Nothing else on the box broke.
ssh home-server.local systemctl is-active transmission display-manager
ssh home-server.local docker ps --format '{{.Names}}'
```

Then reboot (`sudo reboot`, hand it to the user) and re-run the two `curl`s. A
proxy that works until the next boot is the most likely way this silently fails.

**The 409-not-200 detail catches people out**: `/transmission/rpc` returning 409
is a healthy daemon. Only `/` and `/transmission/web/` return 200.

## Scope

Self-contained. Depends on nothing from the session-decoupling work beyond the
already-working `transmission.local` name and the daemon's RPC settings, both
described above. See `home-server-session-decoupling.md` for how those got there.
