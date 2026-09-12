---
name: traefik-up
description: Start the shared Traefik reverse proxy that fronts web apps running on this machine, so several apps share one published port and one public hostname or tunnel. Use when asked to expose a local web app, set up or restart the local reverse proxy or ingress, or when a tunnelled app redirects to localhost or rejects its own WebSocket connections. Not for configuring a proxy in production.
---

# Start the shared reverse proxy

```
pwsh ./scripts/traefik-up.ps1 [-PublicHost <host:port>] [-CertDir <path>] [-Port 8080] [-Dashboard] [-Json]
```

One proxy, one published port, many backends. Apps opt in with docker labels,
so nothing here needs editing when an app is added. `-PublicHost` and
`-CertDir` are needed on the first run and remembered afterwards.

## What it provides to backends

Two pieces of shared configuration that backends reference by name:

- `bc-transport@file` opens a **second TLS connection** to the backend and
  validates it against `ca.crt` in the cert directory. The app then sees
  `https` natively instead of inferring it from `X-Forwarded-Proto`, which is
  what OAuth redirect URIs and `Secure` cookies key off.
- `publichost@file` restores the `Host` and `Origin` request headers to the
  public address.

## Why Origin matters

A devtunnel relay rewrites **both `Host` and `Origin`** to `localhost:<port>`
regardless of its `--host-header` and `--origin-header` flags. `Host` breaks
OAuth redirects, sending the browser to localhost. `Origin` breaks WebSockets:
a server that compares `Origin` against its configured public URL answers 403
with an empty body, so the socket never upgrades and the app hangs part-loaded.
Restoring both at the proxy is the fix, and it is why backends should not be
exposed through the tunnel directly.

Behind a proxy on a real DNS name, neither rewrite is needed.

## Dashboard

Off unless `-Dashboard` is passed, because it is unauthenticated. Do not leave
it on when the public port is reachable from outside the machine.

## The tunnel itself

This skill does not manage the tunnel. Point the tunnel at the proxy's
published port so every backend is reachable through one port, for example a
devtunnel forwarding 8080 with anonymous access enabled. Anonymous matters for
OAuth: the relay answers an unauthenticated GET with a 302 but an
unauthenticated POST with a 401, and the `form_post` callback is a POST.
