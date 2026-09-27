---
name: bc-describe
description: List every endpoint a Business Central instance exposes — web client, dev, OData, API, management, client services — with its URL and auth mode, optionally probing each for a status code. Use when asked which URL or port to use for BC, where the dev or API endpoint is, how to reach a BC instance, or to check which BC endpoints are answering.
---

# Describe BC endpoints

```
pwsh ./scripts/bc-describe.ps1 [<name>] [-Probe] [-Json]
```

With no name it covers every instance. `-Probe` additionally reports the
status code each endpoint answers with, using the instance's credentials.

Ports come from the instance manifest and the BC server instance name from the
running container's configuration, so nothing is guessed. Never quote default
ports from memory: only the first instance gets the familiar 7049.

## What the endpoints are

| Endpoint | Shape | Auth |
|---|---|---|
| web client (public) | `https://<public-host>/<instance>/` | Entra or NavUserPassword |
| web client (direct) | `https://localhost:<port>/<instance>/` | bypasses the proxy |
| dev | `http://localhost:<port>/<server-instance>/dev` | basic |
| OData v4 | `.../<server-instance>/ODataV4` | basic |
| API v2.0 | `.../<server-instance>/api/v2.0` | basic |
| management, client services | | internal |

## Verifying a web client actually works

```
pwsh ./scripts/bc-webclient-signin.ps1 <name> [-Url <public url>] [-DisableHttp2] [-Screenshot <path>]
```

A status code proves Kestrel is up and nothing more. This signs in with the
instance's own credentials, read from the container, and reports whether a Role
Center rendered, what the `/csh` WebSocket did, and which requests returned 4xx.
It clicks the devtunnel interstitial and reads every frame, so it does not
report a working client as broken. Exit code is non-zero when no Role Center
appears.

`-DisableHttp2` is a diagnosis, not a workaround: if the run fails with
`WebSocket handshake: Unexpected response code: 400` and passes with the flag,
the HTTPS listener is offering HTTP/2 through ALPN and BC's `/csh` needs
HTTP/1.1. Reaching the same client through Traefik does not hit this.

## Two things that mislead

- **OData and the API are on different host ports.** The HttpSys stub cannot
  bind overlapping path prefixes on one socket, so it splits them across
  ports. The `<server-instance>/<area>` path shape is preserved on whichever
  port it lands on, which is what BC tooling actually depends on. Hitting the
  API path on the OData port returns a misleading
  `Resource not found for the segment` 404 rather than a redirect.
- **A 401 from the API says nothing about web client sign-in.** Bearer access
  to the API needs a BC API permission the web client does not use. Probe with
  basic auth, or read the web client status instead.

- **A curl probe looks healthier than a browser.** A devtunnel shows an
  anti-phishing interstitial to browsers, once per tunnel, so curl gets the real
  page while a browser stops at "You are about to connect to a developer tunnel"
  and never reaches the sign-in form. A person clicks Continue once.
- **The web client renders the SPA in an iframe.** `body.innerText` of the outer
  document shows only the chrome, so a Role Center that has loaded fine reads as
  empty. Concatenate every frame's text before deciding it failed. `OPEN` then
  `FRAME` on the `/csh` WebSocket with no 4xx means the session is up whatever
  the outer document says.

SOAP is reachable only inside the container network and is reported as such.
