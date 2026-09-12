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

SOAP is reachable only inside the container network and is reported as such.
